// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./proxy.sol";

contract PocProxy is baseProxy{
     constructor(address admin ,address impl) {
        _setAdmin(admin);
        _setLogic(impl);
    }
}