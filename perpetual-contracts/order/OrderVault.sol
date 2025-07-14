// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../tokens/IWETH.sol";
import "../base/CustomAddress.sol";
import "./IOrderVault.sol";

contract OrderVault is IOrderVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using CustomAddress for address payable;

    address public gov;
    address public immutable weth;
    mapping(address => bool) public isHandler;
    mapping(address => bool) public tokenWhitelist; // Optional: whitelisted tokens

    event UpdateGov(address gov);
    event UpdateHandler(address handler, bool isActive);
    event UpdateTokenWhitelist(address token, bool isWhitelisted);
    event Received(address sender, uint256 amount);
    event EthDeposited(address sender, uint256 amount);
    event TokenReceived(address sender, address token, uint256 amount);
    event Withdrawn(address recipient, uint256 amount);
    event TokenWithdrawn(address recipient, address token, uint256 amount);

    error NotGov();
    error NotHandler();
    error ZeroAddress();
    error InvalidETHSender();
    error NoneETH();
    error InvalidAmount();
    error NotWhitelisted();
    error InsufficientETH();
    error InsufficientWeth();
    error FailedWithdrawWeth();
    error InsufficientToken();

    modifier onlyGov() {
        if (msg.sender != gov) { revert NotGov(); }
        _;
    }

    modifier onlyHandler() {
        if (!isHandler[msg.sender]) { revert NotHandler(); }
        _;
    }

    constructor(address _weth) {
        if (_weth == address(0)) { revert ZeroAddress(); }
        weth = _weth;
        gov = msg.sender;
    }

    receive() external payable {
        if (!isHandler[msg.sender]) { revert InvalidETHSender(); }
        emit Received(msg.sender, msg.value);
    }

    function setGov(address _gov) external onlyGov {
        if (_gov == address(0)) { revert ZeroAddress(); }
        gov = _gov;
        emit UpdateGov(_gov);
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
        emit UpdateHandler(_handler, _isActive);
    }

    function setTokenWhitelist(address _token, bool _isWhitelisted) external onlyGov {
        tokenWhitelist[_token] = _isWhitelisted;
        emit UpdateTokenWhitelist(_token, _isWhitelisted);
    }

    function depositEth() external payable {
        if (msg.value == 0) { revert NoneETH(); }
        emit EthDeposited(msg.sender, msg.value);
    }

    function depositToken(address _token, uint256 _amount) external {
        if (_amount == 0) { revert InvalidAmount(); }
        if (!tokenWhitelist[_token]) { revert NotWhitelisted(); }
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        emit TokenReceived(msg.sender, _token, _amount);
    }

    function depositTokenFrom(address _from, address _token, uint256 _amount) external {
        if (_amount == 0) { revert InvalidAmount(); }
        if (!tokenWhitelist[_token]) { revert NotWhitelisted(); }
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        emit TokenReceived(_from, _token, _amount);
    }

    function withdrawEth(address _to, uint256 _amount) external onlyHandler nonReentrant {
        if (_amount > address(this).balance) { revert InsufficientETH(); }
        payable(_to).sendValue(_amount);
        emit Withdrawn(_to, _amount);
    }

    function withdrawWeth(address _to, uint256 _amount) external onlyHandler nonReentrant {
        if (IERC20(weth).balanceOf(address(this)) < _amount) { revert InsufficientWeth(); }
        (bool success, ) = address(weth).call(abi.encodeWithSignature("withdraw(uint256)", _amount));
        if (!success) { revert FailedWithdrawWeth(); }
        payable(_to).sendValue(_amount);
        emit Withdrawn(_to, _amount);
    }

    function withdrawToken(address _to, address _token, uint256 _amount) external onlyHandler nonReentrant {
        if (!tokenWhitelist[_token]) { revert NotWhitelisted(); }
        if (_amount > IERC20(_token).balanceOf(address(this))) { revert InsufficientToken(); }
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokenWithdrawn(_to, _token, _amount);
    }

    function balanceOfEth() external view returns (uint256) {
        return address(this).balance;
    }

    function balanceOfToken(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}