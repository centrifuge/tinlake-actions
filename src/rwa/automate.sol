// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import "./rwa.sol";

contract RWAOperatorAutomation is RWAOperatorActions {

    uint immutable public utilizationLimit = 80*10**25;

    // --- View methods ---
    function currentCapacity(address token) public view returns (uint) {
      // if this is too difficult, alternatively we could calculate the capacities off-chain, pass them, and check it using validate()
      return 0;
    }

}
