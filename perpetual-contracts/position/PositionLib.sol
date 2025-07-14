// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataBase} from "../repo/DataBase.sol";
import "../utils/Keys.sol";
import "../repo/Dao.sol";
import "../pool/IPoolToken.sol";
import "../oracle/PriceLib.sol";
import "../vault/VaultLib.sol";
import "../exception/Errs.sol";

library PositionLib {
    struct Position {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        uint256 size;
        uint256 collateral;
        uint256 collateralAmount;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
        bool isLong;
    }

    struct PositionOut {
        bytes32 key;
        address poolToken;
        address indexToken;
        address collateralToken;
        bool isLong;
        uint256 size;
        uint256 collateral;
        uint256 collateralAmount;
        uint256 averagePrice;
        uint256 entryFundingRate;
        bool hasRealisedProfit;
        uint256 realisedPnl;
        uint256 lastIncreasedTime;
        bool hasProfit;
        uint256 profitDelta;
    }

    struct IncreasePositionRequest {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        uint256 sizeDelta;
        uint256 collateralAmount;
        bool isLong;
    }

    struct IncreasePositionCache {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        uint256 sizeDelta;
        bool isLong;
    }

    struct DecreasePositionCache {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
    }

    struct DecreasePositionRequest {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
    }

    struct LiquidatePositionCache {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        bool isLong;
        address feeReceiver;
    }

    struct MarginFeeParams {
        address account;
        address poolToken;
        address indexToken;
        address collateralToken;
        uint256 size;
        uint256 sizeDelta;
        uint256 entryFundingRate;
        bool isLong;
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;

    error MustBeWithdrawn();
    error LessThanCollateral();

    function getPositionKey(address _account, address _poolToken, address _collateralToken, address _indexToken, bool _isLong) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            _account,
            _poolToken,
            _collateralToken,
            _indexToken,
            _isLong
        ));
    }

    function getNextAveragePrice(DataBase _dataBase, address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _nextPrice, uint256 _sizeDelta, uint256 _lastIncreasedTime) internal view returns (uint256) {
        (bool hasProfit, uint256 delta) = getDelta(_dataBase, _indexToken, _size, _averagePrice, _isLong, _lastIncreasedTime);
        uint256 nextSize = _size + _sizeDelta;
        uint256 divisor;
        if (_isLong) {
            divisor = hasProfit ? (nextSize + delta) : (nextSize - delta);
        } else {
            divisor = hasProfit ? (nextSize - delta) : (nextSize + delta);
        }
        return _nextPrice * nextSize / divisor;
    }

    function getDelta(DataBase _dataBase, address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 /*_lastIncreasedTime*/) internal view returns (bool, uint256) {
        if (_averagePrice <= 0) {
            revert Errs.InvalidAveragePrice();
        }
        uint256 price = _isLong ? PriceLib.pricesMin(_dataBase, _indexToken) : PriceLib.pricesMax(_dataBase, _indexToken);
        uint256 priceDelta = _averagePrice > price ? (_averagePrice - price) : (price - _averagePrice);
        uint256 delta = _size * priceDelta / _averagePrice;

        bool hasProfit;

        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

//        // if the minProfitTime has passed then there will be no min profit threshold
//        // the min profit threshold helps to prevent front-running issues
//        uint256 minBps = block.timestamp > _lastIncreasedTime.add(minProfitTime) ? 0 : minProfitBasisPoints[_indexToken];
//        if (hasProfit && delta.mul(BASIS_POINTS_DIVISOR) <= _size.mul(minBps)) {
//            delta = 0;
//        }

        return (hasProfit, delta);
    }


//    struct Position {
//        address account;
//        address poolToken;
//        address indexToken;
//        address collateralToken;
//        uint256 size;
//        uint256 collateral;
//        uint256 averagePrice;
//        uint256 entryFundingRate;
//        uint256 reserveAmount;
//        int256 realisedPnl;
//        uint256 lastIncreasedTime;
//        bool isLong;
//    }

    bytes32 public constant POS_ACCOUNT = keccak256(abi.encode("POS_ACCOUNT"));
    bytes32 public constant POS_POOL = keccak256(abi.encode("POS_POOL"));
    bytes32 public constant POS_INDEX = keccak256(abi.encode("POS_INDEX"));
    bytes32 public constant POS_COLLATERAL = keccak256(abi.encode("POS_COLLATERAL"));
    bytes32 public constant POS_SIZE = keccak256(abi.encode("POS_SIZE"));
    bytes32 public constant POS_COLLATERAL_USD = keccak256(abi.encode("POS_COLLATERAL_USD"));
    bytes32 public constant POS_COLLATERAL_AMOUNT = keccak256(abi.encode("POS_COLLATERAL_AMOUNT"));
    bytes32 public constant POS_AVERAGE_PRICE = keccak256(abi.encode("POS_AVERAGE_PRICE"));
    bytes32 public constant POS_ENTRY_FUNDING_RATE = keccak256(abi.encode("POS_ENTRY_FUNDING_RATE"));
    bytes32 public constant POS_RESERVE_AMOUNT = keccak256(abi.encode("POS_RESERVE_AMOUNT"));
    bytes32 public constant POS_REALISED_PNL = keccak256(abi.encode("POS_REALISED_PNL"));
    bytes32 public constant POS_LAST_INCREASED_TIME = keccak256(abi.encode("POS_LAST_INCREASED_TIME"));
    bytes32 public constant POS_IS_LONG = keccak256(abi.encode("POS_IS_LONG"));

    function savePosition(DataBase _dataBase, Position memory _position) internal {
        bytes32 _posKey = getPositionKey(_position.account, _position.poolToken, _position.collateralToken, _position.indexToken, _position.isLong);
        addBytes32(_dataBase, Keys.accountPositionList(_position.account, _position.poolToken), _posKey);
        addBytes32(_dataBase, Keys.poolPositionList(_position.poolToken), _posKey);
        setFieldAccount(_dataBase, _posKey, _position.account);
        setFieldPool(_dataBase, _posKey, _position.poolToken);
        setFieldIndex(_dataBase, _posKey, _position.indexToken);
        setFieldCollateral(_dataBase, _posKey, _position.collateralToken);
        setFieldSize(_dataBase, _posKey, _position.size);
        setFieldCollateralUsd(_dataBase, _posKey, _position.collateral);
        setFieldCollateralAmount(_dataBase, _posKey, _position.collateralAmount);
        setFieldAveragePrice(_dataBase, _posKey, _position.averagePrice);
        setFieldEntryFundingRate(_dataBase, _posKey, _position.entryFundingRate);
        setFieldReserveAmount(_dataBase, _posKey, _position.reserveAmount);
        setFieldRealisedPnl(_dataBase, _posKey, _position.realisedPnl);
        setFieldLastIncreasedTime(_dataBase, _posKey, _position.lastIncreasedTime);
        setFieldIsLong(_dataBase, _posKey, _position.isLong);
    }

    function removePosition(DataBase _dataBase, address _account, address _poolToken, bytes32 _posKey) internal {
        removeBytes32(_dataBase, Keys.accountPositionList(_account, _poolToken), _posKey);
        removeBytes32(_dataBase, Keys.poolPositionList(_poolToken), _posKey);
        _dataBase.removeAddress(keccak256(abi.encode(POS_ACCOUNT, _posKey)));
        _dataBase.removeAddress(keccak256(abi.encode(POS_POOL, _posKey)));
        _dataBase.removeAddress(keccak256(abi.encode(POS_INDEX, _posKey)));
        _dataBase.removeAddress(keccak256(abi.encode(POS_COLLATERAL, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_SIZE, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_COLLATERAL_USD, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_COLLATERAL_AMOUNT, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_AVERAGE_PRICE, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_ENTRY_FUNDING_RATE, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_RESERVE_AMOUNT, _posKey)));
        _dataBase.removeInt(keccak256(abi.encode(POS_REALISED_PNL, _posKey)));
        _dataBase.removeUint(keccak256(abi.encode(POS_LAST_INCREASED_TIME, _posKey)));
        _dataBase.removeBool(keccak256(abi.encode(POS_IS_LONG, _posKey)));
    }

    function getPosition(DataBase _dataBase, bytes32 _posKey) internal view returns (Position memory) {
        Position memory position = Position({
            account: getFieldAccount(_dataBase, _posKey),
            poolToken: getFieldPool(_dataBase, _posKey),
            indexToken: getFieldIndex(_dataBase, _posKey),
            collateralToken: getFieldCollateral(_dataBase, _posKey),
            size: getFieldSize(_dataBase, _posKey),
            collateral: getFieldCollateralUsd(_dataBase, _posKey),
            collateralAmount: getFieldCollateralAmount(_dataBase, _posKey),
            averagePrice: getFieldAveragePrice(_dataBase, _posKey),
            entryFundingRate: getFieldEntryFundingRate(_dataBase, _posKey),
            reserveAmount: getFieldReserveAmount(_dataBase, _posKey),
            realisedPnl: getFieldRealisedPnl(_dataBase, _posKey),
            lastIncreasedTime: getFieldLastIncreasedTime(_dataBase, _posKey),
            isLong: getFieldIsLong(_dataBase, _posKey)
        });
        return position;
    }

    function getPositionFields(DataBase _dataBase, address _account, address _poolToken, address _collateralToken, address _indexToken, bool _isLong) internal view returns (uint256, uint256) {
        bytes32 _posKey = getPositionKey(_account, _poolToken, _collateralToken, _indexToken, _isLong);
        return (getFieldSize(_dataBase, _posKey), getFieldCollateralUsd(_dataBase, _posKey));
    }

    function setFieldAccount(DataBase _dataBase, bytes32 _posKey, address _value) internal {
        setAddress(_dataBase, keccak256(abi.encode(POS_ACCOUNT, _posKey)), _value);
    }

    function getFieldAccount(DataBase _dataBase, bytes32 _posKey) internal view returns (address) {
        return _dataBase.getAddress(keccak256(abi.encode(POS_ACCOUNT, _posKey)));
    }

    function setFieldPool(DataBase _dataBase, bytes32 _posKey, address _value) internal {
        setAddress(_dataBase, keccak256(abi.encode(POS_POOL, _posKey)), _value);
    }

    function getFieldPool(DataBase _dataBase, bytes32 _posKey) internal view returns (address) {
        return _dataBase.getAddress(keccak256(abi.encode(POS_POOL, _posKey)));
    }

    function setFieldIndex(DataBase _dataBase, bytes32 _posKey, address _value) internal {
        setAddress(_dataBase, keccak256(abi.encode(POS_INDEX, _posKey)), _value);
    }

    function getFieldIndex(DataBase _dataBase, bytes32 _posKey) internal view returns (address) {
        return _dataBase.getAddress(keccak256(abi.encode(POS_INDEX, _posKey)));
    }

    function setFieldCollateral(DataBase _dataBase, bytes32 _posKey, address _value) internal {
        setAddress(_dataBase, keccak256(abi.encode(POS_COLLATERAL, _posKey)), _value);
    }

    function getFieldCollateral(DataBase _dataBase, bytes32 _posKey) internal view returns (address) {
        return _dataBase.getAddress(keccak256(abi.encode(POS_COLLATERAL, _posKey)));
    }

    function setFieldSize(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_SIZE, _posKey)), _value);
    }

    function getFieldSize(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_SIZE, _posKey)));
    }

    function setFieldCollateralUsd(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_COLLATERAL_USD, _posKey)), _value);
    }

    function getFieldCollateralUsd(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_COLLATERAL_USD, _posKey)));
    }

    function setFieldCollateralAmount(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_COLLATERAL_AMOUNT, _posKey)), _value);
    }

    function getFieldCollateralAmount(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_COLLATERAL_AMOUNT, _posKey)));
    }

    function setFieldAveragePrice(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_AVERAGE_PRICE, _posKey)), _value);
    }

    function getFieldAveragePrice(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_AVERAGE_PRICE, _posKey)));
    }

    function setFieldEntryFundingRate(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_ENTRY_FUNDING_RATE, _posKey)), _value);
    }

    function getFieldEntryFundingRate(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_ENTRY_FUNDING_RATE, _posKey)));
    }

    function setFieldReserveAmount(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_RESERVE_AMOUNT, _posKey)), _value);
    }

    function getFieldReserveAmount(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_RESERVE_AMOUNT, _posKey)));
    }

    function setFieldRealisedPnl(DataBase _dataBase, bytes32 _posKey, int256 _value) internal {
        setInt(_dataBase, keccak256(abi.encode(POS_REALISED_PNL, _posKey)), _value);
    }

    function getFieldRealisedPnl(DataBase _dataBase, bytes32 _posKey) internal view returns (int256) {
        return _dataBase.getInt(keccak256(abi.encode(POS_REALISED_PNL, _posKey)));
    }

    function setFieldLastIncreasedTime(DataBase _dataBase, bytes32 _posKey, uint256 _value) internal {
        setUint(_dataBase, keccak256(abi.encode(POS_LAST_INCREASED_TIME, _posKey)), _value);
    }

    function getFieldLastIncreasedTime(DataBase _dataBase, bytes32 _posKey) internal view returns (uint256) {
        return _dataBase.getUint(keccak256(abi.encode(POS_LAST_INCREASED_TIME, _posKey)));
    }

    function setFieldIsLong(DataBase _dataBase, bytes32 _posKey, bool _value) internal {
        setBool(_dataBase, keccak256(abi.encode(POS_IS_LONG, _posKey)), _value);
    }

    function getFieldIsLong(DataBase _dataBase, bytes32 _posKey) internal view returns (bool) {
        return _dataBase.getBool(keccak256(abi.encode(POS_IS_LONG, _posKey)));
    }
//    bytes32 public constant POS_IS_LONG = keccak256(abi.encode("POS_IS_LONG"));


    function addBytes32(DataBase _dataBase, bytes32 _setKey, bytes32 _value) internal {
        if (!_dataBase.containsBytes32(_setKey, _value)) {
            _dataBase.addBytes32(_setKey, _value);
        }
    }

    function removeBytes32(DataBase _dataBase, bytes32 _setKey, bytes32 _value) internal {
        if (!_dataBase.containsBytes32(_setKey, _value)) {
            _dataBase.removeBytes32(_setKey, _value);
        }
    }

    function setAddress(DataBase _dataBase, bytes32 _key, address _value) internal {
        if (_dataBase.getAddress(_key) != _value) {
            _dataBase.setAddress(_key, _value);
        }
    }

    function setUint(DataBase _dataBase, bytes32 _key, uint256 _value) internal {
        if (_dataBase.getUint(_key) != _value) {
            _dataBase.setUint(_key, _value);
        }
    }

    function setInt(DataBase _dataBase, bytes32 _key, int256 _value) internal {
        if (_dataBase.getInt(_key) != _value) {
            _dataBase.setInt(_key, _value);
        }
    }

    function setBool(DataBase _dataBase, bytes32 _key, bool _value) internal {
        if (_dataBase.getBool(_key) != _value) {
            _dataBase.setBool(_key, _value);
        }
    }

    function addPositionKey(DataBase _dataBase, address _account, address _poolToken, bytes32 _key) internal {
        Dao.addBytes32(_dataBase, Keys.accountPositionList(_account, _poolToken), _key);
    }

    function removePositionKey(DataBase _dataBase, address _account, address _poolToken, bytes32 _key) internal {
        Dao.removeBytes32(_dataBase, Keys.accountPositionList(_account, _poolToken), _key);
    }

    function getPositionKeys(DataBase _dataBase, address _account, address _poolToken) internal view returns (bytes32[] memory) {
        uint256 positionCount = Dao.getBytes32Count(_dataBase, Keys.accountPositionList(_account, _poolToken));
        return Dao.getBytes32ValuesAt(_dataBase, Keys.accountPositionList(_account, _poolToken), 0, positionCount);
    }

    function getPositionFee(DataBase _dataBase, address /* _account */, address _poolToken, address /* _collateralToken */, address /* _indexToken */, bool /* _isLong */, uint256 _sizeDelta) internal view returns (uint256) {
        if (_sizeDelta == 0) { return 0; }
        uint256 afterFeeUsd = _sizeDelta * (BASIS_POINTS_DIVISOR - Dao.marginFeeBasisPoints(_dataBase, _poolToken)) / BASIS_POINTS_DIVISOR;
        return _sizeDelta - afterFeeUsd;
    }

    function getFundingFee(DataBase _dataBase, address /* _account */, address _poolToken, address _collateralToken, address /* _indexToken */, bool /* _isLong */, uint256 _size, uint256 _entryFundingRate) internal view returns (uint256) {
        if (_size == 0) { return 0; }

        uint256 fundingRate = Dao.fundingRate(_dataBase, _poolToken, _collateralToken) - _entryFundingRate;
        if (fundingRate == 0) { return 0; }

        return _size * fundingRate / FUNDING_RATE_PRECISION;
    }

    function getEntryFundingRate(DataBase _dataBase, address _poolToken, address _collateralToken, address /* _indexToken */, bool /* _isLong */) internal view returns (uint256) {
        return Dao.fundingRate(_dataBase, _poolToken, _collateralToken);
    }

//    function validateLiquidation(address _account, address _poolToken, address _collateralToken, address _indexToken, bool _isLong, bool _raise) public view override returns (uint256, uint256)
    function validateLiquidation(DataBase _dataBase, Position memory position, bool _raise) internal view returns (uint256, uint256) {
        (bool hasProfit, uint256 delta) = getDelta(_dataBase, position.indexToken, position.size, position.averagePrice, position.isLong, position.lastIncreasedTime);
        uint256 marginFees = getFundingFee(_dataBase, position.account, position.poolToken, position.collateralToken, position.indexToken, position.isLong, position.size, position.entryFundingRate);
        marginFees = marginFees + getPositionFee(_dataBase, position.account, position.poolToken, position.collateralToken, position.indexToken, position.isLong, position.size);

        if (!hasProfit && position.collateral < delta) {
            if (_raise) { revert Errs.LossesExceedCollateral(); }
            return (1, marginFees);
        }

        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral - delta;
        }

        if (remainingCollateral < marginFees) {
            if (_raise) { revert Errs.FeesExceedCollateral(); }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral);
        }

        if (remainingCollateral < (marginFees + Dao.liquidationFeeUsd(_dataBase, position.poolToken))) {
            if (_raise) { revert Errs.LiquidationFeesExceedCollateral(); }
            return (1, marginFees);
        }

        if (remainingCollateral * Dao.maxLeverage(_dataBase, position.poolToken, position.indexToken) < position.size * BASIS_POINTS_DIVISOR) {
            if (_raise) { revert Errs.MaxLeverageExceeded(); }
            return (2, marginFees);
        }

        return (0, marginFees);
    }

    function shouldDeductFee(
        DataBase _dataBase,
        address _account,
        address _poolToken,
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _increasePositionBufferBps
    ) internal view returns (bool) {
        // if the position is a short, do not charge a fee
        if (!_isLong) { return false; }

        // if the position size is not increasing, this is a collateral deposit
        if (_sizeDelta == 0) { return true; }

        address collateralToken = _path[_path.length - 1];

        (uint256 size, uint256 collateral) = getPositionFields(_dataBase, _account, _poolToken, collateralToken, _indexToken, _isLong);

        // if there is no existing position, do not charge a fee
        if (size == 0) { return false; }

        uint256 nextSize = size + _sizeDelta;
        uint256 collateralDelta = PriceLib.tokenToUsdMin(_dataBase, collateralToken, Dao.tokenDecimals(_dataBase, collateralToken), _amountIn);
        uint256 nextCollateral = collateral + collateralDelta;

        uint256 prevLeverage = size * BASIS_POINTS_DIVISOR / collateral;
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        uint256 nextLeverage = nextSize * (BASIS_POINTS_DIVISOR + _increasePositionBufferBps) / nextCollateral;

//        emit LeverageDecreased(collateralDelta, prevLeverage, nextLeverage);

        // deduct a fee if the leverage is decreased
        return nextLeverage < prevLeverage;
    }

    function validateTokens(DataBase _dataBase, address _poolToken, address _indexToken, address _collateralToken) internal view {
        if (!_dataBase.containsAddress(Keys.indexTokenList(_poolToken), _indexToken)) {
            revert Errs.InvalidIndexToken();
        }
        if (!_dataBase.containsAddress(Keys.stableTokenList(_poolToken), _collateralToken)) {
            revert Errs.InvalidStableToken();
        }
    }

    function validatePosition(uint256 _size, uint256 _collateral) internal pure {
        if (_size == 0) {
            if (_collateral > 0) {
                revert MustBeWithdrawn();
            }
            return;
        }
        if (_size < _collateral) {
            revert LessThanCollateral();
        }
    }

}