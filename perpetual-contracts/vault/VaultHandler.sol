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
import "./IVaultHandler.sol";
import "./VaultLib.sol";
import "../tokens/IUSDG.sol";
import "../swap/SwapUtils.sol";
import "../exception/Errs.sol";
import "../event/EventLogger.sol";

contract VaultHandler is ReentrancyGuard, IVaultHandler {
    using SafeERC20 for IERC20;

    DataBase public immutable dataBase;
    EventLogger public immutable eventLogger;
    address public override usdg;
    address public override gov;
    bool public override isInitialized;
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
        gov = _gov;
        emit UpdateGov(_gov);
    }

    function initialize(address _usdg) external onlyGov {
        if (isInitialized) {
            revert Errs.Initialized();
        }
        isInitialized = true;
        usdg = _usdg;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
        emit UpdateHandler(_handler, _isActive);
    }

    function buyUSDG(address _poolToken, address _token, address _to) external override nonReentrant onlyHandler returns (uint256) {
        VaultLib.validateStableToken(dataBase, _poolToken, _token);

        uint256 tokenAmount = VaultLib.transferIn(dataBase, address(this), _token);
        if (tokenAmount == 0) {
            revert Errs.NoTokenAmountIn(_token);
        }
        VaultLib.transferOut(dataBase, address(this), _token, tokenAmount, _poolToken);
        VaultLib.updateCumulativeFundingRate(dataBase, _poolToken, _token, _token);

        uint256 decimals = Dao.tokenDecimals(dataBase, _token);
        uint256 price = PriceLib.pricesMin(dataBase, _token);
        uint256 usdgAmount = tokenAmount * price / PriceLib.PRICE_PRECISION;
        usdgAmount = VaultLib.adjustForDecimals(usdgAmount, decimals, VaultLib.USDG_DECIMALS);
        if (usdgAmount == 0) {
            revert Errs.InvalidUSDGAmount();
        }

        uint256 feeBasisPoints = getBuyUsdgFeeBasisPoints(_poolToken, _token, usdgAmount);
        (uint256 feeUsd, uint256 feeAmount) = SwapUtils.collectSwapFees(dataBase, _poolToken, _token, decimals, tokenAmount, feeBasisPoints);
        uint256 amountAfterFees = tokenAmount - feeAmount;
        uint256 mintAmount = amountAfterFees * price / PriceLib.PRICE_PRECISION;
        mintAmount = VaultLib.adjustForDecimals(mintAmount, decimals, VaultLib.USDG_DECIMALS);

        VaultLib.increaseUsdgAmount(dataBase, _poolToken, _token, mintAmount);
        VaultLib.increasePoolAmount(dataBase, _poolToken, _token, amountAfterFees);

        IUSDG(usdg).mint(_to, mintAmount);

        eventLogger.emitCollectSwapFees(_poolToken, _token, feeUsd, feeAmount);
        eventLogger.emitBuyUSDG(_poolToken, _token, tokenAmount, mintAmount, feeBasisPoints);
        return mintAmount;
    }

    function sellUSDG(address _poolToken, address _token, address _receiver) external override nonReentrant onlyHandler returns (uint256) {
        VaultLib.validateStableToken(dataBase, _poolToken, _token);

        uint256 usdgAmount = VaultLib.transferIn(dataBase, address(this), usdg);
        if (usdgAmount == 0) {
            revert Errs.NoUSDGAmountIn();
        }

        VaultLib.updateCumulativeFundingRate(dataBase, _poolToken, _token, _token);

        uint256 decimals = Dao.tokenDecimals(dataBase, _token);
        uint256 redemptionAmount = VaultLib.getRedemptionAmount(dataBase, _token, decimals, usdgAmount);
        if (redemptionAmount == 0) {
            revert Errs.InvalidRedemptionAmount(_token);
        }

        VaultLib.decreaseUsdgAmount(dataBase, _poolToken, _token, usdgAmount);
        VaultLib.decreasePoolAmount(dataBase, _poolToken, _token, redemptionAmount);

        IUSDG(usdg).burn(address(this), usdgAmount);

        VaultLib.updateTokenBalance(dataBase, address(this), usdg);

        uint256 feeBasisPoints = getSellUsdgFeeBasisPoints(_poolToken, _token, usdgAmount);
        (uint256 feeUsd, uint256 feeAmount) = SwapUtils.collectSwapFees(dataBase, _poolToken, _token, decimals, redemptionAmount, feeBasisPoints);
        uint256 amountOut = redemptionAmount - feeAmount;
        if (amountOut == 0) {
            revert Errs.NoTokenAmountOut(_token);
        }

        VaultLib.validateBufferAmount(dataBase, _poolToken, _token);
        VaultLib.poolTransferOut(dataBase, _poolToken, _token, amountOut, _receiver);

        eventLogger.emitCollectSwapFees(_poolToken, _token, feeUsd, feeAmount);
        eventLogger.emitSellUSDG(_receiver, _poolToken, _token, usdgAmount, amountOut, feeBasisPoints);

        return amountOut;
    }

    function getBuyUsdgFeeBasisPoints(address _poolToken, address _token, uint256 _usdgAmount) internal view returns (uint256) {
        return VaultLib.getFeeBasisPoints(dataBase, _poolToken, _token, _usdgAmount, Dao.mintFeeBasisPoints(dataBase, _poolToken), Dao.taxBasisPoints(dataBase, _poolToken), true);
    }

    function getSellUsdgFeeBasisPoints(address _poolToken, address _token, uint256 _usdgAmount) internal view returns (uint256) {
        return VaultLib.getFeeBasisPoints(dataBase, _poolToken, _token, _usdgAmount, Dao.burnFeeBasisPoints(dataBase, _poolToken), Dao.taxBasisPoints(dataBase, _poolToken), false);
    }
}