// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

// NOTE: init libraries are imported from `migrate/` while they await their PRs into the
// component repos. Once landed and added as submodules, flip these imports to
// `../../lib/diamond-pau/deploy/PAUInit.sol` etc. — the file contents are identical.

import {
    AdministeredAgentInit,
    AdministeredAgentInitParams
} from "../../migrate/pau-administered-agent/deploy/AdministeredAgentInit.sol";

import { PAUInit, PAUInstance } from "../../migrate/diamond-pau/deploy/PAUInit.sol";

/**
 * @notice Test stand-in for the governance proxy (PauseProxy / SubProxy) executing a spell
 *         action. The init libraries are internal-functions-only, so they inline here and every
 *         wrapped call executes with this contract as `msg.sender` — exactly as they would
 *         execute inside a delegatecalled spell action.
 */
contract SpellHarness {

    function initPAU(PAUInstance memory inst, bytes32[] memory integrationIds) external {
        PAUInit.init(inst, integrationIds);
    }

    function addAllocator(PAUInstance memory inst, address agent) external {
        PAUInit.addAllocator(inst, agent);
    }

    function setIntegrations(PAUInstance memory inst, bytes32[] memory ids) external {
        PAUInit.setIntegrations(inst, ids);
    }

    function removeIntegrations(PAUInstance memory inst, bytes32[] memory ids) external {
        PAUInit.removeIntegrations(inst, ids);
    }

    function initAgent(address agent, AdministeredAgentInitParams memory p) external {
        AdministeredAgentInit.init(agent, p);
    }

    /// @notice Arbitrary governance call, mimicking direct (inlined) spell calls such as
    ///         `rateLimits.setRateLimitData(...)`.
    function exec(address target, bytes calldata data) external returns (bytes memory result) {
        bool success;
        (success, result) = target.call(data);
        require(success, "SpellHarness/call-failed");
    }

}
