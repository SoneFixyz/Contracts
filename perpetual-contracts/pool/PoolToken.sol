// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../repo/DataBase.sol";
import "./Vault.sol";
import "./IPoolToken.sol";

contract PoolToken is ERC20, Vault, IPoolToken, ReentrancyGuard {
    constructor(RoleBase _roleBase, DataBase _dataBase) ERC20("ASTR Perpetual Liquidity Token", "APLP") Vault(_roleBase, _dataBase) {
    }

    function transferOut(address _token, address _to, uint256 _amount) external onlyDataWriter nonReentrant {
        _transferOut(_token, _to, _amount);
    }

    function transferOutNT(address _to, uint256 _amount) external onlyDataWriter nonReentrant {
        address _wnt = TokenLib.wnt(dataBase);
        _transferOutNT(_wnt, _to, _amount);
    }

    function mint(address _account, uint256 _amount) external onlyDataWriter {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyDataWriter {
        _burn(_account, _amount);
    }
}