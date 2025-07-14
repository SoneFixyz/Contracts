// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/CustomAddress.sol";
import "./IOrderRouter.sol";
import "../tokens/IWETH.sol";
import "../oracle/PriceLib.sol";
import "../oracle/IOracle.sol";
import "../position/PositionLib.sol";
import "../position/IIncreasePositionHandler.sol";
import "../position/IDecreasePositionHandler.sol";
import "./OrderBase.sol";
import "./OrderVault.sol";
import "./OrderDao.sol";
import "../event/OrderLogger.sol";
import "./OrderUtils.sol";
import "../position/PositionDao.sol";

contract OrderRouter is IOrderRouter, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using CustomAddress for address payable;

    OrderBase public immutable orderBase;
    OrderVault public immutable orderVault;
    OrderLogger public immutable orderLogger;

    uint256 public MIN_UPDATE_INTERVAL = 30;
    address public admin;
    DataBase public dataBase;
    address public oracle;
    address public gov;
    address public weth;
    address public increasePositionHandler;
    address public decreasePositionHandler;
    address public multicall;
    uint256 public minExecutionFee;
    uint256 public minPurchaseTokenAmountUsd;
    bool public isInitialized = false;
    mapping (address => bool) public isManager;

    event Initialize(
        address oracle,
        address increasePositionHandler,
        address decreasePositionHandler,
        address weth,
        uint256 minExecutionFee,
        uint256 minPurchaseTokenAmountUsd
    );
    event UpdateMinExecutionFee(uint256 minExecutionFee);
    event UpdateMinPurchaseTokenAmountUsd(uint256 minPurchaseTokenAmountUsd);
    event UpdateIncreasePositionHandler(address positionHandler);
    event UpdateDecreasePositionHandler(address positionHandler);
    event UpdateGov(address gov);

    error InvalidSender();
    error UnauthorizedGov();
    error UnauthorizedManager();
    error AlreadyInitialized();
    error InsufficientExecutionFee();
    error OnlyWethWrapped();
    error IncorrectTransferredValue();
    error IncorrectExecutionFee();
    error UnsupportedPurchaseToken();
    error PathLengthExceeded();
    error InsufficientCollateral();
    error UnauthorizedMuticall();
    error ZeroAddress();
    error TooShortUpdateInterval();
    error NonExistentOrder();
    error InvalidPriceForExecution();
    error FailedTransferETHToOrderVault();
    error FailedTransferETHToReceiver();

    modifier onlyGov() {
        if (msg.sender != gov) { revert UnauthorizedGov(); }
        _;
    }

    modifier onlyManager() {
        if (!isManager[msg.sender]) { revert UnauthorizedManager(); }
        _;
    }

    constructor(OrderBase _orderBase, OrderVault _orderVault, OrderLogger _orderLogger, DataBase _dataBase) {
        orderBase = _orderBase;
        orderVault = _orderVault;
        orderLogger = _orderLogger;
        dataBase = _dataBase;
        gov = msg.sender;
    }

    function initialize(
        address _oracle,
        address _increasePositionHandler,
        address _decreasePositionHandler,
        address _weth,
        uint256 _minExecutionFee,
        uint256 _minPurchaseTokenAmountUsd
    ) external onlyGov {
        if (isInitialized) {
            revert AlreadyInitialized();
        }
        isInitialized = true;

        oracle = _oracle;
        increasePositionHandler = _increasePositionHandler;
        decreasePositionHandler = _decreasePositionHandler;
        weth = _weth;
        minExecutionFee = _minExecutionFee;
        minPurchaseTokenAmountUsd = _minPurchaseTokenAmountUsd;

        emit Initialize(_oracle, _increasePositionHandler, _decreasePositionHandler, _weth, _minExecutionFee, _minPurchaseTokenAmountUsd);
    }

    receive() external payable {
        if (msg.sender != weth) { revert InvalidSender(); }
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyGov {
        minExecutionFee = _minExecutionFee;

        emit UpdateMinExecutionFee(_minExecutionFee);
    }

    function setMinPurchaseTokenAmountUsd(uint256 _minPurchaseTokenAmountUsd) external onlyGov {
        minPurchaseTokenAmountUsd = _minPurchaseTokenAmountUsd;

        emit UpdateMinPurchaseTokenAmountUsd(_minPurchaseTokenAmountUsd);
    }

    function setIncreasePositionHandler(address _positionHandler) external onlyGov {
        increasePositionHandler = _positionHandler;

        emit UpdateIncreasePositionHandler(_positionHandler);
    }

    function setDecreasePositionHandler(address _positionHandler) external onlyGov {
        decreasePositionHandler = _positionHandler;

        emit UpdateDecreasePositionHandler(_positionHandler);
    }

    function setGov(address _gov) external onlyGov {
        if (_gov != address(0)) {
            gov = _gov;
            emit UpdateGov(_gov);
        }
    }

    function setManager(address _manager, bool _isManager) external onlyGov {
        isManager[_manager] = _isManager;
    }

    function setMulticall(address _multicall) external onlyGov {
        multicall = _multicall;
    }

    function cancelMultiple(
        address _poolToken,
        uint256[] memory _swapOrderIndexes,
        uint256[] memory _increaseOrderIndexes,
        uint256[] memory _decreaseOrderIndexes
    ) external {
        for (uint256 i = 0; i < _increaseOrderIndexes.length; i++) {
            cancelIncreaseOrder(_poolToken, _increaseOrderIndexes[i]);
        }
        for (uint256 i = 0; i < _decreaseOrderIndexes.length; i++) {
            cancelDecreaseOrder(_poolToken, _decreaseOrderIndexes[i]);
        }
    }

    function increaseOrdersIndex(address _account, address _poolToken) external view returns (uint256) {
        return OrderDao.getIncreaseIndex(orderBase, _account, _poolToken);
    }

    function decreaseOrdersIndex(address _account, address _poolToken) external view returns (uint256) {
        return OrderDao.getDecreaseIndex(orderBase, _account, _poolToken);
    }

    function createIncreaseOrder(
        address _poolToken,
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap
    ) external payable nonReentrant {
        _transferInAndOutETH();

        if (_executionFee < minExecutionFee) { revert InsufficientExecutionFee(); }
        if (_shouldWrap) {
            if (_path[0] != weth) { revert OnlyWethWrapped(); }
            if (msg.value != (_executionFee + _amountIn)) { revert IncorrectTransferredValue(); }
        } else {
            if (msg.value != _executionFee) { revert IncorrectExecutionFee(); }
            IERC20(_path[0]).safeTransferFrom(msg.sender, address(orderVault), _amountIn);
        }

        address _purchaseToken = _path[_path.length - 1];
        if (_purchaseToken != _collateralToken) {
            revert UnsupportedPurchaseToken();
        }
        uint256 _purchaseTokenAmount;
        if (_path.length > 1) {
            revert PathLengthExceeded();
        } else {
            _purchaseTokenAmount = _amountIn;
        }

        {
            uint256 _purchaseTokenAmountUsd = PriceLib.tokenToUsdMin(dataBase, _purchaseToken, _purchaseTokenAmount);
            if (_purchaseTokenAmountUsd < minPurchaseTokenAmountUsd) { revert InsufficientCollateral(); }
        }

        (uint256 _orderIndex, bytes32 _positionKey) = OrderUtils.createIncreaseOrder(
            orderBase,
            msg.sender,
            _poolToken,
            _purchaseToken,
            _purchaseTokenAmount,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );

        orderLogger.emitCreateIncreaseOrder(
            msg.sender,
            _orderIndex,
            _poolToken,
            _purchaseToken,
            _purchaseTokenAmount,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee,
            _positionKey
        );
    }

    function updateIncreaseOrder(address _poolToken, uint256 _orderIndex, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) external nonReentrant {
        bytes32 orderKey = OrderDao.getOrderKey(msg.sender, _orderIndex, _poolToken, OrderDao.ORDER_TYPE_INCREASE);
        OrderDao.IncreaseOrder memory order = OrderDao.getIncreaseOrder(orderBase, orderKey);
        if (order.account == address(0)) { revert NonExistentOrder(); }
        if (block.timestamp <= order.timestamp + MIN_UPDATE_INTERVAL) { revert TooShortUpdateInterval(); }

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        order.timestamp = block.timestamp;
        OrderDao.updateIncreaseOrder(orderBase, order, orderKey);

        orderLogger.emitUpdateIncreaseOrder(
            msg.sender,
            _orderIndex,
            _poolToken,
            order.collateralToken,
            order.indexToken,
            order.isLong,
            _sizeDelta,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function cancelIncreaseOrder(address _poolToken, uint256 _orderIndex) public nonReentrant {
        bytes32 orderKey = OrderDao.getOrderKey(msg.sender, _orderIndex, _poolToken, OrderDao.ORDER_TYPE_INCREASE);
        OrderDao.IncreaseOrder memory order = OrderDao.getIncreaseOrder(orderBase, orderKey);
        if (order.account == address(0)) { revert NonExistentOrder(); }

        OrderDao.removeIncreaseOrder(orderBase, msg.sender, _poolToken, orderKey);

        if (order.purchaseToken == weth) {
            orderVault.withdrawEth(msg.sender, order.executionFee + order.purchaseTokenAmount);
        } else {
            orderVault.withdrawToken(msg.sender, order.purchaseToken, order.purchaseTokenAmount);
            orderVault.withdrawEth(msg.sender, order.executionFee);
        }

        orderLogger.emitCancelIncreaseOrder(
            order.account,
            _orderIndex,
            order.poolToken,
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.collateralToken,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function setPriceMMAndExecuteIncreaseOrder(address[] memory _tokens, PriceLib.Prices[] memory _prices, address _address, address _poolToken, uint256 _orderIndex, address payable _feeReceiver) override external nonReentrant onlyManager {
        _setPricesMM(_tokens, _prices);
        _executeIncreaseOrder(_address, _poolToken, _orderIndex, _feeReceiver);
    }

    function _executeIncreaseOrder(address _address, address _poolToken, uint256 _orderIndex, address payable _feeReceiver) internal {
        bytes32 orderKey = OrderDao.getOrderKey(_address, _orderIndex, _poolToken, OrderDao.ORDER_TYPE_INCREASE);
        OrderDao.IncreaseOrder memory order = OrderDao.getIncreaseOrder(orderBase, orderKey);
        if (order.account == address(0)) { revert NonExistentOrder(); }

        // increase long should use max price
        // increase short should use min price
        (uint256 currentPrice, ) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            order.isLong,
            true
        );

        OrderDao.removeIncreaseOrder(orderBase, _address, _poolToken, orderKey);
        orderVault.withdrawToken(increasePositionHandler, order.purchaseToken, order.purchaseTokenAmount);

        PositionLib.IncreasePositionCache memory cache = PositionLib.IncreasePositionCache({
            account: order.account,
            poolToken: order.poolToken,
            indexToken: order.indexToken,
            collateralToken: order.collateralToken,
            sizeDelta: order.sizeDelta,
            isLong: order.isLong
        });
        IIncreasePositionHandler(increasePositionHandler).increasePosition(cache);

        // pay executor
        orderVault.withdrawEth(_feeReceiver, order.executionFee);

        orderLogger.emitExecuteIncreaseOrder(
            order.account,
            _orderIndex,
            order.poolToken,
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.collateralToken,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            currentPrice
        );
    }

    function createDecreaseOrder(
        address _poolToken,
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable nonReentrant {
        _transferInAndOutETH();

        if (msg.value < minExecutionFee) { revert InsufficientExecutionFee(); }

        (uint256 _orderIndex, bytes32 _positionKey) = OrderUtils.createDecreaseOrder(
            orderBase,
            msg.sender,
            _poolToken,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value);

        orderLogger.emitCreateDecreaseOrder(
            msg.sender,
            _orderIndex,
            _poolToken,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value,
            _positionKey
        );
    }

    function createDecreaseOrderTpSl(
        address _account,
        address _poolToken,
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable nonReentrant {
        if (msg.sender != multicall) { revert UnauthorizedMuticall(); }
        _transferInAndOutETH();

        if (msg.value <= minExecutionFee) { revert InsufficientExecutionFee(); }
        if (_account == address(0)) { revert ZeroAddress(); }

        (uint256 _orderIndex, bytes32 _positionKey) = OrderUtils.createDecreaseOrder(
            orderBase,
            _account,
            _poolToken,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value);

        orderLogger.emitCreateDecreaseOrder(
            _account,
            _orderIndex,
            _poolToken,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value,
            _positionKey
        );
    }

    function setPriceMMAndExecuteDecreaseOrder(address[] memory _tokens, PriceLib.Prices[] memory _prices, address _address, address _poolToken, uint256 _orderIndex, address payable _feeReceiver) override external nonReentrant onlyManager {
        _setPricesMM(_tokens, _prices);
        _executeDecreaseOrder(_address, _poolToken, _orderIndex, _feeReceiver);
    }

    function _executeDecreaseOrder(address _address, address _poolToken, uint256 _orderIndex, address payable _feeReceiver) internal {
        bytes32 orderKey = OrderDao.getOrderKey(_address, _orderIndex, _poolToken, OrderDao.ORDER_TYPE_DECREASE);
        OrderDao.DecreaseOrder memory order = OrderDao.getDecreaseOrder(orderBase, orderKey);
        if (order.account == address(0)) { revert NonExistentOrder(); }

        // decrease long should use min price
        // decrease short should use max price
        (uint256 currentPrice, ) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            !order.isLong,
            true
        );

        OrderDao.removeDecreaseOrder(orderBase, _address, _poolToken, orderKey);

        PositionLib.DecreasePositionCache memory cache = PositionLib.DecreasePositionCache({
            account: order.account,
            poolToken: order.poolToken,
            indexToken: order.indexToken,
            collateralToken: order.collateralToken,
            collateralDelta: order.collateralDelta,
            sizeDelta: order.sizeDelta,
            isLong: order.isLong,
            receiver: address(this)
        });

        uint256 amountOut = IDecreasePositionHandler(decreasePositionHandler).decreasePosition(cache);

        // transfer released collateral to user
        if (order.collateralToken == weth) {
            _transferOutETH(amountOut, payable(order.account));
        } else {
            IERC20(order.collateralToken).safeTransfer(order.account, amountOut);
        }

        // pay executor
        orderVault.withdrawEth(_feeReceiver, order.executionFee);

        (uint256 _positionSize,) = PositionDao.getPositionFields(dataBase, order.account, order.poolToken,
            order.collateralToken, order.indexToken, order.isLong);
        if (_positionSize == 0) {
            _batchCancelDecreaseOrders(order.account, order.poolToken, order.indexToken, order.isLong);
        }

        orderLogger.emitExecuteDecreaseOrder(
            order.account,
            _orderIndex,
            order.poolToken,
            order.collateralToken,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            currentPrice
        );
    }

    function updateDecreaseOrder(
        address _poolToken,
        uint256 _orderIndex,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        bytes32 orderKey = OrderDao.getOrderKey(msg.sender, _orderIndex, _poolToken, OrderDao.ORDER_TYPE_DECREASE);
        OrderDao.DecreaseOrder memory order = OrderDao.getDecreaseOrder(orderBase, orderKey);
        if (order.account == address(0)) { revert NonExistentOrder(); }
        if (block.timestamp <= order.timestamp + MIN_UPDATE_INTERVAL) { revert TooShortUpdateInterval(); }

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        order.collateralDelta = _collateralDelta;
        order.timestamp = block.timestamp;
        OrderDao.updateDecreaseOrder(orderBase, order, orderKey);

        orderLogger.emitUpdateDecreaseOrder(
            msg.sender,
            _orderIndex,
            order.poolToken,
            order.collateralToken,
            _collateralDelta,
            order.indexToken,
            _sizeDelta,
            order.isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function cancelDecreaseOrder(address _poolToken, uint256 _orderIndex) override public nonReentrant {
        _cancelDecreaseOrder(OrderDao.getOrderKey(msg.sender, _orderIndex, _poolToken, OrderDao.ORDER_TYPE_DECREASE), true);
    }

    function cancelDecreaseOrderByKey(bytes32 _orderKey) override external onlyManager nonReentrant {
        _cancelDecreaseOrder(_orderKey, true);
    }

    function batchCancelDecreaseOrders(address _account, address _poolToken, address _indexToken, bool _isLong) override external onlyManager nonReentrant {
        _batchCancelDecreaseOrders(_account, _poolToken, _indexToken, _isLong);
    }

    function _batchCancelDecreaseOrders(address _account, address _poolToken, address _indexToken, bool _isLong) internal {
        OrderDao.DecreaseOrder[] memory _orders = OrderDao.getDecreaseOrders(orderBase, _account, _poolToken);
        for (uint256 i = 0; i < _orders.length; i++) {
            OrderDao.DecreaseOrder memory _order = _orders[i];
            if (_order.indexToken == _indexToken && _order.isLong == _isLong) {
                _cancelDecreaseOrder(OrderDao.getOrderKey(_account, _order.index, _poolToken, OrderDao.ORDER_TYPE_DECREASE), false);
            }
        }
    }

    function _cancelDecreaseOrder(bytes32 _orderKey, bool _raised) internal {
        OrderDao.DecreaseOrder memory order = OrderDao.getDecreaseOrder(orderBase, _orderKey);
        if (order.account == address(0)) {
            if (_raised) { revert NonExistentOrder(); }
            return;
        }

        OrderDao.removeDecreaseOrder(orderBase, order.account, order.poolToken, _orderKey);
        orderVault.withdrawEth(order.account, order.executionFee);

        orderLogger.emitCancelDecreaseOrder(
            order.account,
            order.index,
            order.poolToken,
            order.collateralToken,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function validatePositionOrderPrice(
        bool _triggerAboveThreshold,
        uint256 _triggerPrice,
        address _indexToken,
        bool _maximizePrice,
        bool _raise
    ) public view returns (uint256, bool) {
        uint256 currentPrice = _maximizePrice
            ? PriceLib.pricesMax(dataBase, _indexToken) : PriceLib.pricesMin(dataBase, _indexToken);
        bool isPriceValid = _triggerAboveThreshold ? currentPrice > _triggerPrice : currentPrice < _triggerPrice;
        if (_raise) {
            if (!isPriceValid) { revert InvalidPriceForExecution(); }
        }
        return (currentPrice, isPriceValid);
    }

    function _transferInAndOutETH() private {
        if (msg.value != 0) {
            (bool success, ) = address(orderVault).call{value: msg.value}("");
            if (!success) { revert FailedTransferETHToOrderVault(); }
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        (bool success, ) = _receiver.call{value: _amountOut}("");
        if (!success) { revert FailedTransferETHToReceiver(); }
    }

    function _setPricesMM(address[] memory _tokens, PriceLib.Prices[] memory _prices) internal {
        IOracle(oracle).batchSetPriceMM(_tokens, _prices);
    }
}