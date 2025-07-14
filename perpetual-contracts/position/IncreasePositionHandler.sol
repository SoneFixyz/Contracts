// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataBase} from "../repo/DataBase.sol";
import "../utils/Keys.sol";
import "../repo/Dao.sol";
import "../pool/IPoolToken.sol";
import "../oracle/PriceLib.sol";
import "./IIncreasePositionHandler.sol";
import "../vault/VaultLib.sol";
import "./PositionDao.sol";
import "./PositionUtils.sol";
import "../event/EventLogger.sol";
import "../referrals/IReferralStorage.sol";
import "./DecreasePositionUtils.sol";
import "../asset/AssetUtils.sol";

contract IncreasePositionHandler is ReentrancyGuard, IIncreasePositionHandler {

    DataBase public immutable dataBase;
    EventLogger public immutable eventLogger;
    address public override gov;
    address public referralStorage;
    address public assetManager;
    mapping (address => bool) public override isHandler;

    event UpdateGov(address gov);
    event UpdateHandler(address handler, bool isActive);
    error Unauthorized(address);

    modifier onlyGov() {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyHandler() {
        if (!isHandler[msg.sender]) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    constructor(DataBase _dataBase, EventLogger _eventLogger) {
        dataBase = _dataBase;
        eventLogger = _eventLogger;
        gov = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        if (_gov != address(0)) {
            gov = _gov;
            emit UpdateGov(_gov);
        }
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
        emit UpdateHandler(_handler, _isActive);
    }

    function setReferralStorage(address _referralStorage) external onlyGov {
        referralStorage = _referralStorage;
    }

    function setAssetManager(address _assetManager) external onlyGov {
        assetManager = _assetManager;
    }

    function increasePosition(PositionLib.IncreasePositionCache memory cache) external override nonReentrant onlyHandler {
        PositionUtils.validateTokens(dataBase, cache.poolToken, cache.indexToken, cache.collateralToken);
        AssetUtils.validateTradingOpen(dataBase, assetManager, cache.indexToken);
        PositionUtils.updateCumulativeFundingRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken);
        PositionUtils.updateCumulativeScaleRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken);

        bytes32 key = PositionDao.getPositionKey(cache.account, cache.poolToken, cache.collateralToken, cache.indexToken, cache.isLong);
        PositionDao.Position memory position = PositionDao.getPosition(dataBase, key);
        if (position.account == address(0)) {
            position.account = cache.account;
            position.poolToken = cache.poolToken;
            position.collateralToken = cache.collateralToken;
            position.indexToken = cache.indexToken;
            position.isLong = cache.isLong;
        }

        uint256 price = cache.isLong ? PriceLib.pricesMax(dataBase, cache.indexToken) : PriceLib.pricesMin(dataBase, cache.indexToken);

        if (position.size == 0) {
            position.averagePrice = price;
        }

        if (position.size > 0 && cache.sizeDelta > 0) {
            position.averagePrice = PositionUtils.getNextAveragePrice(dataBase, cache.indexToken, position.size, position.averagePrice, position.isLong, price, cache.sizeDelta, position.lastIncreasedTime);
        }

        uint256 collateralDelta = VaultLib.transferIn(dataBase, address(this), cache.collateralToken);
        uint256 collateralDeltaUsd = PriceLib.tokenToUsdMin(dataBase, cache.collateralToken, Dao.tokenDecimals(dataBase, cache.collateralToken), collateralDelta);
        VaultLib.transferOut(dataBase, address(this), cache.collateralToken, collateralDelta, cache.poolToken);

        PositionDao.MarginFeeParams memory marginFeeParams = PositionDao.MarginFeeParams({
            account: position.account,
            poolToken: position.poolToken,
            indexToken: position.indexToken,
            collateralToken: position.collateralToken,
            size: position.size,
            sizeDelta: cache.sizeDelta,
            entryFundingRate: position.entryFundingRate,
            isLong: position.isLong
        });
        (uint256 fee, uint256 feeAmount) = PositionUtils.collectMarginFees(dataBase, eventLogger, marginFeeParams, IReferralStorage(referralStorage));
        (bool isClaim, uint256 scaleFee, uint256 scaleFeeTokens) = PositionUtils.collectScaleFee(dataBase, position.account, position.poolToken, position.collateralToken, position.indexToken,
            position.size, position.isLong, position.entryLongScaleRate, position.entryShortScaleRate);
        if (!isClaim) {
            fee += scaleFee;
            feeAmount += scaleFeeTokens;
        }

        position.collateral = position.collateral + collateralDeltaUsd;
        if (position.collateral < fee) {
            revert Errs.InsufficientCollateralForFees(position.collateral, fee);
        }

        position.collateral = position.collateral - fee;
        position.collateralAmount = position.collateralAmount + collateralDelta - feeAmount;
        position.entryFundingRate = PositionUtils.getEntryFundingRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken, cache.isLong);
        position.entryLongScaleRate = PositionDao.longScaleRate(dataBase, cache.poolToken, cache.indexToken);
        position.entryShortScaleRate = PositionDao.shortScaleRate(dataBase, cache.poolToken, cache.indexToken);
        position.size = position.size + cache.sizeDelta;
        position.lastIncreasedTime = block.timestamp;
        if (position.size <= 0) {
            revert Errs.InvalidPositionDotSize();
        }

        PositionUtils.validatePosition(position.size, position.collateral);
        DecreasePositionUtils.validateLiquidation(dataBase, position, true);

        uint256 reserveDelta = PriceLib.usdToTokenMax(dataBase, cache.collateralToken, cache.sizeDelta);
        position.reserveAmount = position.reserveAmount + reserveDelta;
        VaultLib.increaseReservedAmount(dataBase, cache.poolToken, cache.collateralToken, reserveDelta);

        if (cache.isLong) {
            VaultLib.increaseGuaranteedUsd(dataBase, cache.poolToken, cache.collateralToken, cache.sizeDelta + fee);
            VaultLib.decreaseGuaranteedUsd(dataBase, cache.poolToken, cache.collateralToken, collateralDeltaUsd);
            VaultLib.increaseGuaranteedUsd(dataBase, cache.poolToken, cache.indexToken, cache.sizeDelta + fee);
            VaultLib.decreaseGuaranteedUsd(dataBase, cache.poolToken, cache.indexToken, collateralDeltaUsd);

            PositionUtils.increaseGlobalLongSize(dataBase, cache.poolToken, cache.collateralToken, cache.sizeDelta);
            PositionUtils.increaseGlobalLongSize(dataBase, cache.poolToken, cache.indexToken, cache.sizeDelta);
            PositionUtils.increaseAccountLongSize(dataBase, cache.poolToken, cache.indexToken, cache.account, cache.sizeDelta);
        } else {
            if (Dao.globalShortSize(dataBase, cache.poolToken, cache.indexToken) == 0) {
                Dao.setGlobalShortAveragePrice(dataBase, cache.poolToken, cache.indexToken, price);
            } else {
                uint256 nextAveragePrice = VaultLib.getNextGlobalShortAveragePrice(dataBase, cache.poolToken, cache.indexToken, price, cache.sizeDelta);
                Dao.setGlobalShortAveragePrice(dataBase, cache.poolToken, cache.indexToken, nextAveragePrice);
            }

            PositionUtils.increaseGlobalShortSize(dataBase, cache.poolToken, cache.indexToken, cache.sizeDelta);
            PositionUtils.increaseGlobalShortSize(dataBase, cache.poolToken, cache.collateralToken, cache.sizeDelta);
            PositionUtils.increaseAccountShortSize(dataBase, cache.poolToken, cache.indexToken, cache.account, cache.sizeDelta);
        }

        PositionDao.savePosition(dataBase, position);

        eventLogger.emitCollectMarginFees(cache.poolToken, cache.collateralToken, fee, feeAmount);
        eventLogger.emitIncreasePosition(key, cache.account, cache.poolToken, cache.collateralToken, cache.indexToken, collateralDeltaUsd, cache.sizeDelta, cache.isLong, price, fee);
        eventLogger.emitUpdatePosition(key, position.size, position.poolToken, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, position.realisedPnl, price);
        eventLogger.emitCollectFundingFees(position.poolToken, position.collateralToken, scaleFee, scaleFeeTokens, position.account, isClaim);
    }

}