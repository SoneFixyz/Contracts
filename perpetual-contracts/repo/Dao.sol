// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataBase} from "../repo/DataBase.sol";
import "../utils/Keys.sol";

library Dao {

    function wnt(DataBase _dataBase) internal view returns (address) {
        return _dataBase.getAddress(Keys.WNT);
    }

    function setWNT(DataBase _dataBase, address _value) internal {
        _dataBase.setAddress(Keys.WNT, _value);
    }

    function tokenDecimals(DataBase _dataBase, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.tokenDecimals(_token));
    }

    function setTokenDecimals(DataBase _dataBase, address _token, uint256 _decimals) internal {
        _dataBase.setUint(Keys.tokenDecimals(_token), _decimals);
    }

    function stableToken(DataBase _dataBase, address _token) internal view returns (bool) {
        return _dataBase.getBool(Keys.stableToken(_token));
    }

    function addStableToken(DataBase _dataBase, address _token) internal {
        _dataBase.setBool(Keys.stableToken(_token), true);
    }

    function removeStableToken(DataBase _dataBase, address _token) internal {
        _dataBase.removeBool(Keys.stableToken(_token));
    }


    // pool token
    function poolAmount(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.poolAmount(_poolToken, _token));
    }

    function setPoolAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.poolAmount(_poolToken, _token), _amount);
    }

    function bufferAmount(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.bufferAmount(_poolToken, _token));
    }

    function setBufferAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.bufferAmount(_poolToken, _token), _amount);
    }

    function reservedAmount(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.reservedAmount(_poolToken, _token));
    }

    function setReservedAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.reservedAmount(_poolToken, _token), _amount);
    }

    function guaranteedUsd(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.guaranteedUsd(_poolToken, _token));
    }

    function setGuaranteedUsd(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.guaranteedUsd(_poolToken, _token), _value);
    }

    function globalShortSize(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.globalShortSize(_poolToken, _token));
    }

    function setGlobalShortSize(DataBase _dataBase, address _poolToken, address _token, uint256 _size) internal {
        _dataBase.setUint(Keys.globalShortSize(_poolToken, _token), _size);
    }

    function globalShortAveragePrice(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.globalShortAveragePrice(_poolToken, _token));
    }

    function setGlobalShortAveragePrice(DataBase _dataBase, address _poolToken, address _token, uint256 _price) internal {
        _dataBase.setUint(Keys.globalShortAveragePrice(_poolToken, _token), _price);
    }

    function usdgAmount(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.usdgAmount(_poolToken, _token));
    }

    function setUsdgAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.usdgAmount(_poolToken, _token), _amount);
    }

    function feeReserveTo(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.feeReserveTo(_poolToken, _token));
    }

    function setFeeReserveTo(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.feeReserveTo(_poolToken, _token), _value);
    }

    function feeReserveIn(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.feeReserveIn(_poolToken, _token));
    }

    function setFeeReserveIn(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.feeReserveIn(_poolToken, _token), _value);
    }

    function balanceAmount(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.balanceAmount(_poolToken, _token));
    }

    function setBalanceAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.balanceAmount(_poolToken, _token), _value);
    }

    function fundingRate(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.fundingRate(_poolToken, _token));
    }

    function setFundingRate(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.fundingRate(_poolToken, _token), _value);
    }

    function lastFundingTime(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.lastFundingTime(_poolToken, _token));
    }

    function setLastFundingTime(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.lastFundingTime(_poolToken, _token), _value);
    }

    function maxUsdgAmount(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.maxUsdgAmount(_poolToken, _token));
    }

    function setMaxUsdgAmount(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.maxUsdgAmount(_poolToken, _token), _amount);
    }

    function maxGlobalLongSize(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.maxGlobalLongSize(_poolToken, _token));
    }

    function setMaxGlobalLongSize(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.maxGlobalLongSize(_poolToken, _token), _amount);
    }

    function maxGlobalShortSize(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.maxGlobalShortSize(_poolToken, _token));
    }

    function setMaxGlobalShortSize(DataBase _dataBase, address _poolToken, address _token, uint256 _amount) internal {
        _dataBase.setUint(Keys.maxGlobalShortSize(_poolToken, _token), _amount);
    }

    function maxLeverage(DataBase _dataBase, address _poolToken, address _token) internal view returns (uint256) {
        return _dataBase.getUint(Keys.maxLeverage(_poolToken, _token));
    }

    function setMaxLeverage(DataBase _dataBase, address _poolToken, address _token, uint256 _value) internal {
        _dataBase.setUint(Keys.maxLeverage(_poolToken, _token), _value);
    }


    // pool
    function stableTaxBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.stableTaxBasisPoints(_poolToken));
    }

    function setStableTaxBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.stableTaxBasisPoints(_poolToken), _value);
    }

    function taxBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.taxBasisPoints(_poolToken));
    }

    function setTaxBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.taxBasisPoints(_poolToken), _value);
    }

    function mintFeeBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.mintFeeBasisPoints(_poolToken));
    }

    function setMintFeeBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.mintFeeBasisPoints(_poolToken), _value);
    }

    function burnFeeBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.burnFeeBasisPoints(_poolToken));
    }

    function setBurnFeeBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.burnFeeBasisPoints(_poolToken), _value);
    }

    function stableSwapFeeBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.stableSwapFeeBasisPoints(_poolToken));
    }

    function setStableSwapFeeBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.stableSwapFeeBasisPoints(_poolToken), _value);
    }

    function swapFeeBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.swapFeeBasisPoints(_poolToken));
    }

    function setSwapFeeBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.swapFeeBasisPoints(_poolToken), _value);
    }

    function marginFeeBasisPoints(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.marginFeeBasisPoints(_poolToken));
    }

    function setMarginFeeBasisPoints(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.marginFeeBasisPoints(_poolToken), _value);
    }

    function liquidationFeeUsd(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.liquidationFeeUsd(_poolToken));
    }

    function setLiquidationFeeUsd(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.liquidationFeeUsd(_poolToken), _value);
    }

    function hasDynamicFees(DataBase _dataBase, address _poolToken) internal view returns (bool) {
        return _dataBase.getBool(Keys.hasDynamicFees(_poolToken));
    }

    function setHasDynamicFees(DataBase _dataBase, address _poolToken, bool _value) internal {
        _dataBase.setBool(Keys.hasDynamicFees(_poolToken), _value);
    }

    function swapFeeToFactor(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.swapFeeToFactor(_poolToken));
    }

    function setSwapFeeToFactor(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.swapFeeToFactor(_poolToken), _value);
    }

    function positionFeeToFactor(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.positionFeeToFactor(_poolToken));
    }

    function setPositionFeeToFactor(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.positionFeeToFactor(_poolToken), _value);
    }

    function cumulativeFees(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.cumulativeFees(_poolToken));
    }

    function setCumulativeFees(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.cumulativeFees(_poolToken), _value);
    }

    function poolInFees(DataBase _dataBase, address _poolToken) internal view returns (uint256) {
        return _dataBase.getUint(Keys.poolInFees(_poolToken));
    }

    function setPoolInFees(DataBase _dataBase, address _poolToken, uint256 _value) internal {
        _dataBase.setUint(Keys.poolInFees(_poolToken), _value);
    }

    function lastAddedAt(DataBase _dataBase, address _poolToken, address _account) internal view returns (uint256) {
        return _dataBase.getUint(Keys.lastAddedAt(_poolToken, _account));
    }

    function setLastAddedAt(DataBase _dataBase, address _poolToken, address _account, uint256 _value) internal {
        _dataBase.setUint(Keys.lastAddedAt(_poolToken, _account), _value);
    }

    function getBytes32Count(DataBase _dataBase, bytes32 _setKey) internal view returns (uint256) {
        return _dataBase.getBytes32Count(_setKey);
    }

    function getBytes32ValuesAt(DataBase _dataBase, bytes32 _setKey, uint256 _start, uint256 _end) internal view returns (bytes32[] memory) {
        return _dataBase.getBytes32ValuesAt(_setKey, _start, _end);
    }

    function addBytes32(DataBase _dataBase, bytes32 _setKey, bytes32 _value) internal {
        _dataBase.addBytes32(_setKey, _value);
    }

    function removeBytes32(DataBase _dataBase, bytes32 _setKey, bytes32 _value) internal {
        _dataBase.removeBytes32(_setKey, _value);
    }

    function setAddress(DataBase _dataBase, bytes32 _key, address _value) internal {
        _dataBase.setAddress(_key, _value);
    }

    function getAddress(DataBase _dataBase, bytes32 _key) internal view returns (address) {
        return _dataBase.getAddress(_key);
    }
}