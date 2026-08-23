// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Script }  from "../lib/forge-std/src/Script.sol";
import { console } from "../lib/forge-std/src/console.sol";

import {
    AdministeredAgentDeploy,
    AdministeredAgentDeployParams
} from "./dependencies/AdministeredAgentDeploy.sol";

import { PAUDeploy, PAUDeployParams } from "./dependencies/PAUDeploy.sol";

interface IPAUFactoryLike {
    function beacon() external view returns (address);
}

/**
 * @notice Deploys a PAU system: one shared ALMProxy, `stackCount` PAU stacks wired to it, and
 *         `agentCount` AdministeredAgents. Every contract comes out with `owner` (PauseProxy or
 *         SubProxy) as its sole admin; the deployer holds no role on anything.
 *
 *         All wiring and role configuration is left to the activation spell, which calls the
 *         component repos' init libraries (PAUInit / AdministeredAgentInit) with the addresses
 *         exported below.
 *
 * @dev    Input:  script/input/{chainId}/deploy-pau.json
 *                   { "owner", "pauFactory", "agentFactory", "stackCount", "agentCount" }
 *         Output: script/output/{chainId}/deploy-pau-latest.json (all deployed addresses)
 */
contract DeployPAUScript is Script {

    string internal constant NAME = "deploy-pau";

    function run() external {
        string memory root    = vm.projectRoot();
        string memory chainId = vm.toString(block.chainid);

        string memory input = vm.readFile(
            string.concat(root, "/script/input/", chainId, "/", NAME, ".json")
        );

        address pauFactory   = vm.parseJsonAddress(input, ".pauFactory");
        address agentFactory = vm.parseJsonAddress(input, ".agentFactory");
        address owner        = vm.parseJsonAddress(input, ".owner");
        uint256 stackCount   = vm.parseJsonUint(input,    ".stackCount");
        uint256 agentCount   = vm.parseJsonUint(input,    ".agentCount");

        require(stackCount > 0, "DeployPAUScript/zero-stack-count");

        PAUDeployParams memory params = PAUDeployParams({
            pauFactory : pauFactory,
            owner      : owner
        });

        address   almProxy;
        address[] memory accessControls = new address[](stackCount);
        address[] memory rateLimits     = new address[](stackCount);
        address[] memory controllers    = new address[](stackCount);
        address[] memory agents         = new address[](agentCount);

        vm.startBroadcast();

        (accessControls[0], almProxy, rateLimits[0], controllers[0]) = PAUDeploy.deploy(params);

        for (uint256 i = 1; i < stackCount; i++) {
            (accessControls[i], rateLimits[i], controllers[i]) =
                PAUDeploy.deployStack(params, almProxy);
        }

        for (uint256 i = 0; i < agentCount; i++) {
            agents[i] = AdministeredAgentDeploy.deploy(AdministeredAgentDeployParams({
                agentFactory : agentFactory,
                owner        : owner
            }));
        }

        vm.stopBroadcast();

        // Export all deployed addresses for the spell / reviewers.
        string memory out;
        out = vm.serializeAddress(NAME, "owner",          owner);
        out = vm.serializeAddress(NAME, "pauFactory",     pauFactory);
        out = vm.serializeAddress(NAME, "agentFactory",   agentFactory);
        out = vm.serializeAddress(NAME, "almProxy",       almProxy);
        out = vm.serializeAddress(NAME, "beacon",         IPAUFactoryLike(pauFactory).beacon());
        out = vm.serializeAddress(NAME, "accessControls", accessControls);
        out = vm.serializeAddress(NAME, "rateLimits",     rateLimits);
        out = vm.serializeAddress(NAME, "controllers",    controllers);
        out = vm.serializeAddress(NAME, "allocatorAgents", agents);

        string memory outDir = string.concat(root, "/script/output/", chainId, "/");
        vm.createDir(outDir, true);
        vm.writeJson(out, string.concat(outDir, NAME, "-latest.json"));

        console.log("owner:   ", owner);
        console.log("almProxy:", almProxy);

        for (uint256 i = 0; i < stackCount; i++) {
            console.log("stack", i);
            console.log("  accessControls:", accessControls[i]);
            console.log("  rateLimits:    ", rateLimits[i]);
            console.log("  controller:    ", controllers[i]);
        }

        for (uint256 i = 0; i < agentCount; i++) {
            console.log("allocatorAgent", i, agents[i]);
        }
    }

}
