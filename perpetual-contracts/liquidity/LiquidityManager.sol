// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../repo/DataBase.sol";
import "../repo/RoleBase.sol";
import "./LiquidityLib.sol";
import "../pool/IPoolToken.sol";
import "../oracle/PriceLib.sol";
import "../vault/IVaultHandler.sol";
import "../tokens/IUSDG.sol";
import "./ILiquidityManager.sol";
import "../event/EventLogger.sol";

contract LiquidityManager is ILiquidityManager, ReentrancyGuard {
    using SafeERC20 for IERC20;

    DataBase public immutable dataBase;
    RoleBase public immutable roleBase;
    EventLogger public immutable eventLogger;
    address public gov;
    address public usdg;
    address public vaultHandler;
    bool public isInitialized;
    mapping (address => bool) public override isHandler;

    uint256 public cooldownDuration = 600;
    mapping (address => mapping (address => uint256)) public lastAddedAt;

    error Initialized();
    error ZeroTokenAmount();
    error ZeroLpAmount();
    error InsufficientUSDGOut(uint256, uint256);
    error InsufficientLPOut(uint256, uint256);
    error InsufficientTokenOut(address, uint256, uint256);
    error IsCooldown();

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

    constructor(RoleBase _roleBase, DataBase _dataBase, EventLogger _eventLogger) {
        dataBase = _dataBase;
        roleBase = _roleBase;
        eventLogger = _eventLogger;
        gov = msg.sender;
    }

    function initialize(address _usdg) external onlyGov {
        if (isInitialized) {
            revert Initialized();
        }
        isInitialized = true;
        usdg = _usdg;
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

    function setVaultHandler(address _vaultHandler) external onlyGov {
        vaultHandler = _vaultHandler;
    }

    function addLiquidity(address _poolToken, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minLp) external nonReentrant returns (uint256) {
        return _addLiquidity(msg.sender, msg.sender, _poolToken, _token, _amount, _minUsdg, _minLp);
    }

    function addLiquidityForAccount(address _fundingAccount, address _account, address _poolToken, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minLp)
            external nonReentrant onlyHandler returns (uint256) {
        return _addLiquidity(_fundingAccount, _account, _poolToken, _token, _amount, _minUsdg, _minLp);
    }

    function removeLiquidity(address _poolToken, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        return _removeLiquidity(msg.sender, _poolToken, _tokenOut, _lpAmount, _minOut, _receiver);
    }

    function removeLiquidityForAccount(address _account, address _poolToken, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _receiver)
            external nonReentrant onlyHandler returns (uint256) {
        return _removeLiquidity(_account, _poolToken, _tokenOut, _lpAmount, _minOut, _receiver);
    }

    function _addLiquidity(address _fundingAccount, address _account, address _poolToken, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minLp) private returns (uint256) {
        if (_amount <= 0) {
            revert ZeroTokenAmount();
        }

        (address[] memory _assetsTokens, uint256[] memory _assetsPrices) = LiquidityLib.getAssets(dataBase, _poolToken, true);

        uint256 aumInUsdg = LiquidityLib.getAumInUsdg(dataBase, _poolToken, _assetsTokens, _assetsPrices);
        uint256 lpSupply = IERC20(_poolToken).totalSupply();

        IERC20(_token).safeTransferFrom(_fundingAccount, vaultHandler, _amount);
        uint256 usdgAmount = IVaultHandler(vaultHandler).buyUSDG(_poolToken, _token, address(this));
        if (usdgAmount < _minUsdg) {
            revert InsufficientUSDGOut(usdgAmount, _minUsdg);
        }

        uint256 mintAmount = aumInUsdg == 0 ? usdgAmount : usdgAmount * lpSupply / aumInUsdg;
        if (mintAmount < _minLp) {
            revert InsufficientLPOut(mintAmount, _minLp);
        }

        IPoolToken(_poolToken).mint(_account, mintAmount);
        lastAddedAt[_poolToken][_account] = block.timestamp;

        eventLogger.emitAddLiquidity(_account, _poolToken, _token, _amount, aumInUsdg, lpSupply, usdgAmount, mintAmount);
        return mintAmount;
    }

    function _removeLiquidity(address _account, address _poolToken, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _receiver) private returns (uint256) {
        if (_lpAmount <= 0) {
            revert ZeroLpAmount();
        }

        if (lastAddedAt[_poolToken][_account] + cooldownDuration > block.timestamp) {
            revert IsCooldown();
        }

        (address[] memory _assetsTokens, uint256[] memory _assetsPrices) = LiquidityLib.getAssets(dataBase, _poolToken, false);
        uint256 aumInUsdg = LiquidityLib.getAumInUsdg(dataBase, _poolToken, _assetsTokens, _assetsPrices);
        uint256 lpSupply = IERC20(_poolToken).totalSupply();

        uint256 usdgAmount = _lpAmount * aumInUsdg / lpSupply;
        uint256 usdgBalance = IERC20(usdg).balanceOf(address(this));
        if (usdgAmount > usdgBalance) {
            IUSDG(usdg).mint(address(this), usdgAmount - usdgBalance);
        }

        IPoolToken(_poolToken).burn(_account, _lpAmount);

        IERC20(usdg).safeTransfer(vaultHandler, usdgAmount);
        uint256 amountOut = IVaultHandler(vaultHandler).sellUSDG(_poolToken, _tokenOut, _receiver);
        if (amountOut < _minOut) {
            revert InsufficientTokenOut(_tokenOut, amountOut, _minOut);
        }

        eventLogger.emitRemoveLiquidity(_account, _poolToken, _tokenOut, _lpAmount, aumInUsdg, lpSupply, usdgAmount, amountOut);
        return amountOut;
    }

    function getAumInUsdg(address _poolToken, bool _maximize) public view returns (uint256) {
        (address[] memory _assetsTokens, uint256[] memory _assetsPrices) = LiquidityLib.getAssets(dataBase, _poolToken, _maximize);
        return LiquidityLib.getAumInUsdg(dataBase, _poolToken, _assetsTokens, _assetsPrices);
    }

    function getAssets(address _poolToken, bool _maximize) public view returns (address[] memory, uint256[] memory) {
        return LiquidityLib.getAssets(dataBase, _poolToken, _maximize);
    }
}