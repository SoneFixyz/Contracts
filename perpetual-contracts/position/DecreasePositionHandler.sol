// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataBase} from "../repo/DataBase.sol";
import "../oracle/PriceLib.sol";
import "./IDecreasePositionHandler.sol";
import "../vault/VaultLib.sol";
import "./PositionLib.sol";
import "./PositionUtils.sol";
import "./DecreasePositionUtils.sol";
import "../exception/Errs.sol";
import "../event/EventLogger.sol";
import "../referrals/IReferralStorage.sol";
import "../asset/AssetUtils.sol";

contract DecreasePositionHandler is ReentrancyGuard, IDecreasePositionHandler {

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

    function decreasePosition(PositionLib.DecreasePositionCache memory cache) external override nonReentrant onlyHandler returns (uint256) {
        AssetUtils.validateGlobalPaused(assetManager);
        PositionUtils.updateCumulativeFundingRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken);
        PositionUtils.updateCumulativeScaleRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken);

        PositionDao.DecreasePositionCache memory decCache = PositionDao.DecreasePositionCache({
            account: cache.account,
            poolToken: cache.poolToken,
            indexToken: cache.indexToken,
            collateralToken: cache.collateralToken,
            collateralDelta: cache.collateralDelta,
            sizeDelta: cache.sizeDelta,
            isLong: cache.isLong,
            receiver: cache.receiver
        });
        return DecreasePositionUtils.decreasePosition(dataBase, eventLogger, decCache, IReferralStorage(referralStorage));
    }

    function liquidatePosition(PositionLib.LiquidatePositionCache memory cache) external override nonReentrant onlyHandler {
        PositionUtils.updateCumulativeFundingRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken);
        PositionUtils.updateCumulativeScaleRate(dataBase, cache.poolToken, cache.collateralToken, cache.indexToken);

        bytes32 key = PositionUtils.getPositionKey(cache.account, cache.poolToken, cache.collateralToken, cache.indexToken, cache.isLong);
        PositionDao.Position memory position = PositionUtils.getPosition(dataBase, key);
        if (position.size <= 0) {
            revert Errs.EmptyPosition();
        }

        (uint256 liquidationState, uint256 marginFees) = DecreasePositionUtils.validateLiquidation(dataBase, position, false);
        if (liquidationState == 0) {
            revert Errs.CannotBeLiquidated();
        }

        if (liquidationState == 2) {
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead

            PositionDao.DecreasePositionCache memory decCache = PositionDao.DecreasePositionCache({
                account: cache.account,
                poolToken: cache.poolToken,
                indexToken: cache.indexToken,
                collateralToken: cache.collateralToken,
                collateralDelta: 0,
                sizeDelta: position.size,
                isLong: cache.isLong,
                receiver: cache.account
            });

            DecreasePositionUtils.decreasePosition(dataBase, eventLogger, decCache, IReferralStorage(referralStorage));
            return;
        }

        uint256 feeTokens = PriceLib.usdToTokenMin(dataBase, cache.collateralToken, marginFees);
        PositionUtils.collectMarginFees(dataBase, cache.poolToken, cache.collateralToken, feeTokens, marginFees);
        eventLogger.emitCollectMarginFees(cache.poolToken, cache.collateralToken, marginFees, feeTokens);

        PositionUtils.decreaseReservedAmount(dataBase, cache.poolToken, cache.collateralToken, position.reserveAmount);

        if (cache.isLong) {
            VaultLib.decreaseGuaranteedUsd(dataBase, cache.poolToken, cache.collateralToken, position.size - position.collateral);
            VaultLib.decreaseGuaranteedUsd(dataBase, cache.poolToken, cache.indexToken, position.size - position.collateral);
            PositionUtils.decreasePoolAmount(dataBase, cache.poolToken, cache.collateralToken, feeTokens);
        }

        uint256 markPrice = PriceLib.pricesLow(dataBase, cache.indexToken, cache.isLong);
        eventLogger.emitLiquidatePosition(key, cache.account, cache.poolToken, cache.collateralToken, cache.indexToken, cache.isLong, position.size, position.collateral, position.reserveAmount, position.realisedPnl, markPrice);

        if (marginFees < position.collateral) {
            uint256 remainingCollateral = position.collateral - marginFees;
            PositionUtils.increasePoolAmount(dataBase, cache.poolToken, cache.collateralToken, PriceLib.usdToTokenMin(dataBase, cache.collateralToken, remainingCollateral));
        }

        if (cache.isLong) {
            PositionUtils.decreaseGlobalLongSize(dataBase, cache.poolToken, cache.indexToken, position.size);
            PositionUtils.decreaseGlobalLongSize(dataBase, cache.poolToken, cache.collateralToken, position.size);
            PositionUtils.decreaseAccountLongSize(dataBase, cache.poolToken, cache.indexToken, cache.account, position.size);
        } else {
            PositionUtils.decreaseGlobalShortSize(dataBase, cache.poolToken, cache.indexToken, position.size);
            PositionUtils.decreaseGlobalShortSize(dataBase, cache.poolToken, cache.collateralToken, position.size);
            PositionUtils.decreaseAccountShortSize(dataBase, cache.poolToken, cache.indexToken, cache.account, position.size);
        }

        PositionUtils.removePosition(dataBase, cache.account, cache.poolToken, key);

        uint256 liquidationFeeUsd = PositionDao.liquidationFeeUsd(dataBase, cache.poolToken);
        uint256 liquidationFeeAmount = PriceLib.usdToTokenMin(dataBase, cache.collateralToken, liquidationFeeUsd);
        PositionUtils.decreasePoolAmount(dataBase, cache.poolToken, cache.collateralToken, liquidationFeeAmount);

        VaultLib.poolTransferOut(dataBase, cache.poolToken, cache.collateralToken, liquidationFeeAmount, cache.feeReceiver);
    }

}