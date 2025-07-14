// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataBase} from "../repo/DataBase.sol";
import "../utils/Keys.sol";
import "../repo/Dao.sol";
import "./VaultDao.sol";
import "../pool/IPoolToken.sol";
import "../oracle/PriceLib.sol";
import "../position/PositionLib.sol";

library VaultLib {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant USDG_DECIMALS = 18;
    uint256 public constant fundingInterval = 1 hours;
    uint256 public constant fundingRateFactor = 100;
    uint256 public constant stableFundingRateFactor = 100;

    event CollectSwapFees(address poolToken, address token, uint256 feeUsd, uint256 feeTokens);
    event CollectMarginFees(address poolToken, address token, uint256 feeUsd, uint256 feeTokens);
    event IncreasePoolAmount(address poolToken, address token, uint256 amount);
    event InvalidIncreaseEvent(address poolToken, address token, uint256 balance, uint256 nextPoolAmount);
    event DecreasePoolAmount(address poolToken, address token, uint256 amount);
    event IncreaseUsdgAmount(address poolToken, address token, uint256 amount);
    event DecreaseUsdgAmount(address poolToken, address token, uint256 amount);
    event IncreaseReservedAmount(address poolToken, address token, uint256 amount);
    event DecreaseReservedAmount(address poolToken, address token, uint256 amount);
    event IncreaseGuaranteedUsd(address poolToken, address token, uint256 usdAmount);
    event DecreaseGuaranteedUsd(address poolToken, address token, uint256 usdAmount);
    event BuyUSDG(address poolToken, address token, uint256 tokenAmount, uint256 mintAmount, uint256 feeBasisPoints);
    event UpdateFundingRate(address poolToken, address token, uint256 fundingRate);

    error NoAmountIn(address, address);
    error InvalidUSDGAmount();
    error InvalidIncrease(address, address, uint256, uint256);
    error PoolAmountExceeded(address poolToken, address token, uint256 poolAmount, uint256 decAmount);
    error ReservedAmountExceeded(address poolToken, address token, uint256 poolAmount, uint256 reservedAmount);
    error PoolLessThanBuffer(address poolToken, address token, uint256 poolAmount, uint256 bufferAmount);
    error ReservedExceedsPool(address poolToken, address token, uint256 reservedAmount, uint256 poolAmount);
    error InsufficientReserved(address poolToken, address token, uint256 reservedAmount, uint256 decAmount);
    error InvalidIndexToken();
    error InvalidStableToken();

    function getFeeBasisPoints(DataBase _dataBase, address _poolToken, address /*_token*/, uint256 /*_usdgDelta*/, uint256 _feeBasisPoints, uint256 /*_taxBasisPoints*/, bool /*_increment*/) internal view returns (uint256) {
        if (!Dao.hasDynamicFees(_dataBase, _poolToken)) { return _feeBasisPoints; }
        return _feeBasisPoints;
    }

    function collectSwapFees(DataBase _dataBase, address _poolToken, address _token, uint256 _decimals, uint256 _amount, uint256 _feeBasisPoints) internal returns (uint256) {
        uint256 afterFeeAmount = _amount * (BASIS_POINTS_DIVISOR - _feeBasisPoints) / BASIS_POINTS_DIVISOR;
        uint256 feeAmount = _amount - afterFeeAmount;
        uint256 feeUsdMin = PriceLib.tokenToUsdMin(_dataBase, _token, _decimals, feeAmount);

        updateCumulativeFees(_dataBase, _poolToken, feeUsdMin);
        distributeSwapFees(_dataBase, _poolToken, _token, feeAmount);

        emit CollectSwapFees(_poolToken, _token, feeUsdMin, feeAmount);
        return afterFeeAmount;
    }

    function collectMarginFees(DataBase _dataBase, PositionLib.MarginFeeParams memory params) internal returns (uint256) {
        uint256 feeUsd = PositionLib.getPositionFee(
            _dataBase,
            params.account,
            params.poolToken,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            params.sizeDelta
        );

        uint256 fundingFee = PositionLib.getFundingFee(
            _dataBase,
            params.account,
            params.poolToken,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            params.size,
            params.entryFundingRate
        );
        feeUsd = feeUsd + fundingFee;

        uint256 feeAmount = PriceLib.usdToTokenMin(_dataBase, params.collateralToken, feeUsd);

        updateCumulativeFees(_dataBase, params.poolToken, feeUsd);
        distributeMarginFees(_dataBase, params.poolToken, params.collateralToken, feeAmount);

        emit CollectMarginFees(params.poolToken, params.collateralToken, feeUsd, feeAmount);
        return feeUsd;
    }

    function collectMarginFees(DataBase _dataBase, address _poolToken, address _token, uint256 _feeAmount, uint256 _feeUsd) internal returns (uint256) {
        updateCumulativeFees(_dataBase, _poolToken, _feeUsd);
        distributeMarginFees(_dataBase, _poolToken, _token, _feeAmount);
        emit CollectMarginFees(_poolToken, _token, _feeUsd, _feeAmount);
        return _feeUsd;
    }

    function updateCumulativeFees(DataBase _dataBase, address _poolToken, uint256 feeUsd) internal {
        uint256 cumulativeFees = Dao.cumulativeFees(_dataBase, _poolToken);
        Dao.setCumulativeFees(_dataBase, _poolToken, cumulativeFees + feeUsd);
    }

    function distributeSwapFees(DataBase _dataBase, address _poolToken, address _token, uint256 _feeAmount) internal {
        distributeFees(_dataBase, _poolToken, _token, _feeAmount, Dao.swapFeeToFactor(_dataBase, _poolToken));
    }

    function distributeMarginFees(DataBase _dataBase, address _poolToken, address _token, uint256 _feeAmount) internal {
        distributeFees(_dataBase, _poolToken, _token, _feeAmount, Dao.positionFeeToFactor(_dataBase, _poolToken));
    }

    function distributeFees(DataBase _dataBase, address _poolToken, address _token, uint256 _feeAmount, uint256 _feeToFactor) internal {
        uint256 feeToAmount = _feeAmount * _feeToFactor / BASIS_POINTS_DIVISOR;
        uint256 nextFeeToReserveAmount = Dao.feeReserveTo(_dataBase, _poolToken, _token) + feeToAmount;
        Dao.setFeeReserveTo(_dataBase, _poolToken, _token, nextFeeToReserveAmount);
        uint256 feeInAmount = _feeAmount - feeToAmount;
        uint256 nextFeeInReserveAmount = Dao.feeReserveIn(_dataBase, _poolToken, _token) + feeInAmount;
        Dao.setFeeReserveIn(_dataBase, _poolToken, _token, nextFeeInReserveAmount);
        increasePoolAmount(_dataBase, _poolToken, _token, feeInAmount);

        uint256 feeInUsd = PriceLib.tokenToUsdMin(_dataBase, _token, Dao.tokenDecimals(_dataBase, _token), feeInAmount);
        uint256 poolInFees = Dao.poolInFees(_dataBase, _poolToken);
        Dao.setPoolInFees(_dataBase, _poolToken, poolInFees + feeInUsd);
    }

    function adjustForDecimals(uint256 _amount, uint256 _decimalsDiv, uint256 _decimalsMul) internal pure returns (uint256) {
        return _amount * 10 ** _decimalsMul / 10 ** _decimalsDiv;
    }

    function increaseUsdgAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 usdgAmount = Dao.usdgAmount(_dataBase, _poolToken, _token);
        Dao.setUsdgAmount(_dataBase, _poolToken, _token, usdgAmount + _amount);
        emit IncreaseUsdgAmount(_poolToken, _token, _amount);
    }

    function decreaseUsdgAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 usdgAmount = Dao.usdgAmount(_dataBase, _poolToken, _token);
        if (usdgAmount <= _amount) {
            Dao.setUsdgAmount(_dataBase, _poolToken, _token, 0);
            emit DecreaseUsdgAmount(_poolToken, _token, usdgAmount);
            return;
        }
        Dao.setUsdgAmount(_dataBase, _poolToken, _token, usdgAmount - _amount);
        emit DecreaseUsdgAmount(_poolToken, _token, _amount);
    }

    function increasePoolAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 nextPoolAmount = Dao.poolAmount(_dataBase, _poolToken, _token) + _amount;
        Dao.setPoolAmount(_dataBase, _poolToken, _token, nextPoolAmount);
        uint256 balance = IERC20(_token).balanceOf(_poolToken);
        if (nextPoolAmount > balance) {
            emit InvalidIncreaseEvent(_poolToken, _token, balance, nextPoolAmount);
        }
        emit IncreasePoolAmount(_poolToken, _token, _amount);
    }

    function decreasePoolAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 curPoolAmount = Dao.poolAmount(_dataBase, _poolToken, _token);
        if (curPoolAmount < _amount) {
            revert PoolAmountExceeded(_poolToken, _token, curPoolAmount, _amount);
        }
        uint256 nextPoolAmount = curPoolAmount - _amount;
        Dao.setPoolAmount(_dataBase, _poolToken, _token, nextPoolAmount);
        uint256 reservedAmount = Dao.reservedAmount(_dataBase, _poolToken, _token);
        if (reservedAmount > nextPoolAmount) {
            revert ReservedAmountExceeded(_poolToken, _token, nextPoolAmount, reservedAmount);
        }
        emit DecreasePoolAmount(_poolToken, _token, _amount);
    }

    function increaseReservedAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 nextReservedAmount = Dao.reservedAmount(_dataBase, _poolToken, _token) + _amount;
        Dao.setReservedAmount(_dataBase, _poolToken, _token, nextReservedAmount);
        uint256 curPoolAmount = Dao.poolAmount(_dataBase, _poolToken, _token);
        if (nextReservedAmount > curPoolAmount) {
            revert ReservedExceedsPool(_poolToken, _token, nextReservedAmount, curPoolAmount);
        }
        emit IncreaseReservedAmount(_poolToken, _token, _amount);
    }

    function decreaseReservedAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 curReservedAmount = Dao.reservedAmount(_dataBase, _poolToken, _token);
        if (curReservedAmount < _amount) {
            revert InsufficientReserved(_poolToken, _token, curReservedAmount, _amount);
        }
        Dao.setReservedAmount(_dataBase, _poolToken, _token, curReservedAmount - _amount);
        emit DecreaseReservedAmount(_poolToken, _token, _amount);
    }

    function increaseGuaranteedUsd(DataBase _dataBase, address _poolToken, address _token, uint256 _usdAmount) internal {
        uint256 guaranteedUsd = Dao.guaranteedUsd(_dataBase, _poolToken, _token);
        Dao.setGuaranteedUsd(_dataBase, _poolToken, _token, guaranteedUsd + _usdAmount);
        emit IncreaseGuaranteedUsd(_poolToken, _token, _usdAmount);
    }

    function decreaseGuaranteedUsd(DataBase _dataBase, address _poolToken, address _token, uint256 _usdAmount) internal {
        uint256 guaranteedUsd = Dao.guaranteedUsd(_dataBase, _poolToken, _token);
        if (guaranteedUsd > _usdAmount) {
            Dao.setGuaranteedUsd(_dataBase, _poolToken, _token, guaranteedUsd - _usdAmount);
        } else {
            Dao.setGuaranteedUsd(_dataBase, _poolToken, _token, 0);
        }
        emit DecreaseGuaranteedUsd(_poolToken, _token, _usdAmount);
    }

    function increaseGlobalShortSize(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 size = Dao.globalShortSize(_dataBase, _poolToken, _token);
        Dao.setGlobalShortSize(_dataBase, _poolToken, _token, size + _amount);
    }

    function updateCumulativeFundingRate(DataBase _dataBase, address _poolToken, address _collateralToken, address /*_indexToken*/) internal {
        if (Dao.lastFundingTime(_dataBase, _poolToken, _collateralToken) == 0) {
            Dao.setLastFundingTime(_dataBase, _poolToken, _collateralToken, block.timestamp / fundingInterval * fundingInterval);
            return;
        }

        if ((Dao.lastFundingTime(_dataBase, _poolToken, _collateralToken) + fundingInterval) > block.timestamp) {
            return;
        }

        uint256 fundingRate = getNextFundingRate(_dataBase, _poolToken, _collateralToken);
        Dao.setFundingRate(_dataBase, _poolToken, _collateralToken, Dao.fundingRate(_dataBase, _poolToken, _collateralToken) + fundingRate);
        Dao.setLastFundingTime(_dataBase, _poolToken, _collateralToken, block.timestamp / fundingInterval * fundingInterval);

        emit UpdateFundingRate(_poolToken, _collateralToken, Dao.fundingRate(_dataBase, _poolToken, _collateralToken));
    }

    function getNextFundingRate(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        uint256 lastFundingTime = Dao.lastFundingTime(_dataBase, _poolToken, _token);
        if ((lastFundingTime + fundingInterval) > block.timestamp) { return 0; }

        uint256 intervals = (block.timestamp - lastFundingTime) / fundingInterval;
        uint256 poolAmount = Dao.poolAmount(_dataBase, _poolToken, _token);
        if (poolAmount == 0) { return 0; }

        uint256 _fundingRateFactor = Dao.stableToken(_dataBase, _token) ? stableFundingRateFactor : fundingRateFactor;
        return _fundingRateFactor * Dao.reservedAmount(_dataBase, _poolToken, _token) * intervals / poolAmount;
    }

    function getNextGlobalShortAveragePrice(DataBase _dataBase, address _poolToken, address _indexToken, uint256 _nextPrice, uint256 _sizeDelta) internal view returns (uint256) {
        uint256 size = Dao.globalShortSize(_dataBase, _poolToken, _indexToken);
        uint256 averagePrice = Dao.globalShortAveragePrice(_dataBase, _poolToken, _indexToken);
        uint256 priceDelta = averagePrice > _nextPrice ? averagePrice - _nextPrice : _nextPrice - averagePrice;
        uint256 delta = size * priceDelta / averagePrice;
        bool hasProfit = averagePrice > _nextPrice;

        uint256 nextSize = size + _sizeDelta;
        uint256 divisor = hasProfit ? nextSize - delta : nextSize + delta;

        return _nextPrice * nextSize / divisor;
    }

    function decreaseGlobalShortSize(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        uint256 size = Dao.globalShortSize(_dataBase, _poolToken, _token);
        if (_amount > size) {
            Dao.setGlobalShortSize(_dataBase, _poolToken, _token, 0);
            return;
        }
        Dao.setGlobalShortSize(_dataBase, _poolToken, _token, size - _amount);
    }

    function transferIn(DataBase _dataBase, address _owner, address _token) internal returns (uint256) {
        uint256 prevBalance = Dao.balanceAmount(_dataBase, _owner, _token);
        uint256 nextBalance = IERC20(_token).balanceOf(_owner);
        Dao.setBalanceAmount(_dataBase, _owner, _token, nextBalance);

        return nextBalance - prevBalance;
    }

    function transferOut(DataBase _dataBase, address _owner, address _token, uint256 _amount, address _receiver) internal {
        if (_owner == address(this)) {
            IERC20(_token).safeTransfer(_receiver, _amount);
        } else {
            IERC20(_token).safeTransferFrom(_owner, _receiver, _amount);
        }
        updateTokenBalance(_dataBase, _owner, _token);
    }

    function poolTransferOut(DataBase _dataBase, address _poolToken, address _token, uint256 _amount, address _receiver) internal {
        IPoolToken(_poolToken).transferOut(_token, _receiver, _amount);
        updateTokenBalance(_dataBase, _poolToken, _token);
    }

    function getRedemptionAmount(DataBase _dataBase, address _token, uint256 _decimals, uint256 _usdgAmount) internal view returns (uint256) {
        uint256 price = PriceLib.pricesMax(_dataBase, _token);
        uint256 redemptionAmount = _usdgAmount * PriceLib.PRICE_PRECISION / price;
        return adjustForDecimals(redemptionAmount, VaultLib.USDG_DECIMALS, _decimals);
    }

    function updateTokenBalance(DataBase _dataBase, address _owner, address _token) internal {
        uint256 nextBalance = IERC20(_token).balanceOf(_owner);
        Dao.setBalanceAmount(_dataBase, _owner, _token, nextBalance);
    }

    function validateBufferAmount(DataBase _dataBase, address _poolToken, address _token) internal view {
        uint256 poolAmount = Dao.poolAmount(_dataBase, _poolToken, _token);
        uint256 bufferAmount = Dao.bufferAmount(_dataBase, _poolToken, _token);
        if (poolAmount < bufferAmount) {
            revert PoolLessThanBuffer(_poolToken, _token, poolAmount, bufferAmount);
        }
    }

    function validateStableToken(DataBase _dataBase, address _poolToken, address _token) internal view {
        if (!VaultDao.poolStableToken(_dataBase, _poolToken, _token)) {
            revert InvalidStableToken();
        }
    }

    function validateIndexToken(DataBase _dataBase, address _poolToken, address _token) internal view {
        if (!VaultDao.poolIndexToken(_dataBase, _poolToken, _token)) {
            revert InvalidIndexToken();
        }
    }
}