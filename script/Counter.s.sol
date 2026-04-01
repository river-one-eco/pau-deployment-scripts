// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { Script, console2 } from "forge-std/Script.sol";

contract DeployAllFacetsMainnet is Script {

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ScriptTools.exportContract(fileSlug, "aaveFacet", new AaveFacet());
        ScriptTools.exportContract(fileSlug, "psmFacet", new PSMFacet(Ethereum.DAI, Ethereum.USDC,...));
    }
}

contract DeployAllFacetsBase is Script {

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ScriptTools.exportContract(fileSlug, "aaveFacet", new AaveFacet());
    }

}
