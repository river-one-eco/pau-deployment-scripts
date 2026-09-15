// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import {
    AdministeredAgentDeploy,
    AdministeredAgentDeployParams
} from "../../script/dependencies/AdministeredAgentDeploy.sol";

import { PAUDeploy, PAUDeployParams } from "../../script/dependencies/PAUDeploy.sol";

import {
    AdministeredAgentInitParams
} from "../../migrate/pau-administered-agent/deploy/AdministeredAgentInit.sol";

import { PAUInstance } from "../../migrate/diamond-pau/deploy/PAUInit.sol";

import { SpellHarness } from "../utils/SpellHarness.sol";

interface IAdministeredAgentLike {

    error NotActor();

    function call(address target, bytes memory data) external payable returns (bytes memory result);

}

interface IControllerLike {

    function transferAsset_transfer(address asset, address destination, uint256 amount) external;

    function transferAsset_getTransferRateLimitKey(address asset, address destination) external view returns (bytes32);

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IPAUFactoryLike {

    function beacon() external view returns (address);

}

interface IRateLimitsLike {

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    function getCurrentRateLimit(bytes32 key) external view returns (uint256);

}

/**
 * @notice Full end-to-end integration on the script + init-library path: {PAUDeploy} deploys a
 *         real PAU stack (real Beacon, PAUFactory, Controller, ALMProxy, RateLimits) owned by a
 *         {SpellHarness} standing in for governance, the harness runs {PAUInit} /
 *         {AdministeredAgentInit} the way a spell action would (registering a real
 *         TransferAssetFacet integration), then an actor routes a real ERC20 transfer through
 *         AdministeredAgent -> Controller -> facet -> ALMProxy -> token.
 */
contract ScriptPath_TransferAsset_Integration_Tests is Test {

    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant USDC                       = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 internal constant TRANSFER_ASSET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    address internal allocator = makeAddr("allocator");
    address internal deployer  = makeAddr("deployer");
    address internal recipient = makeAddr("recipient");

    SpellHarness internal governance;

    PAUInstance internal inst;

    address internal allocatorAgent;

    bytes32 internal transferRateLimitKey;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        governance = new SpellHarness();

        // Deployment leg: run by the deployer, grants everything to governance.

        vm.startPrank(deployer);

        inst = this.deployPAUExternal(
            PAUDeployParams({ pauFactory: PAU_FACTORY, owner: address(governance) })
        );

        allocatorAgent = this.deployAgentExternal(
            AdministeredAgentDeployParams({
                agentFactory : ADMINISTERED_AGENT_FACTORY,
                owner        : address(governance)
            })
        );

        vm.stopPrank();

        // Spell leg: init libraries + direct calls, executed as governance.

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = TRANSFER_ASSET_INTEGRATION_ID;

        governance.initPAU(inst, integrationIds);

        address[] memory actors = new address[](1);
        actors[0] = allocator;

        governance.initAgent(allocatorAgent, AdministeredAgentInitParams({
            admins   : new address[](0),
            actors   : actors,
            grantors : new address[](0),
            revokers : new address[](0)
        }));

        governance.addAllocator(inst, allocatorAgent);

        // Fund the proxy and set the rate limit for this asset/destination pair (a direct,
        // inlined spell call — not init-library surface).

        deal(USDC, inst.almProxy, 1_500_000e6);

        transferRateLimitKey =
            IControllerLike(inst.controller).transferAsset_getTransferRateLimitKey(USDC, recipient);

        governance.exec(
            inst.rateLimits,
            abi.encodeWithSelector(
                IRateLimitsLike.setRateLimitData.selector,
                transferRateLimitKey,
                uint256(2_000_000e6),
                uint256(0)
            )
        );
    }

    // External wrappers so the deploy libraries execute in a frame whose msg.sender can be
    // pranked to `deployer`.
    function deployPAUExternal(PAUDeployParams memory p)
        external
        returns (PAUInstance memory inst_)
    {
        (inst_.accessControls, inst_.almProxy, inst_.rateLimits, inst_.controller) =
            PAUDeploy.deploy(p);

        inst_.beacon = IPAUFactoryLike(p.pauFactory).beacon();
    }

    function deployAgentExternal(AdministeredAgentDeployParams memory p)
        external
        returns (address agent)
    {
        agent = AdministeredAgentDeploy.deploy(p);
    }

    function test_endToEnd_transferAsset() external {
        assertEq(IERC20Like(USDC).balanceOf(inst.almProxy), 1_500_000e6);
        assertEq(IERC20Like(USDC).balanceOf(recipient),     0);

        assertEq(
            IRateLimitsLike(inst.rateLimits).getCurrentRateLimit(transferRateLimitKey),
            2_000_000e6
        );

        vm.prank(allocator);
        IAdministeredAgentLike(allocatorAgent).call(
            inst.controller,
            abi.encodeWithSelector(IControllerLike.transferAsset_transfer.selector, USDC, recipient, 1_100_000e6)
        );

        assertEq(IERC20Like(USDC).balanceOf(inst.almProxy), 400_000e6);
        assertEq(IERC20Like(USDC).balanceOf(recipient),     1_100_000e6);

        assertEq(
            IRateLimitsLike(inst.rateLimits).getCurrentRateLimit(transferRateLimitKey),
            900_000e6
        );
    }

    // Sanity: only an actor on the agent can drive the transfer.
    function test_endToEnd_revertsForNonActor() external {
        vm.prank(makeAddr("non-actor"));
        vm.expectRevert(IAdministeredAgentLike.NotActor.selector);
        IAdministeredAgentLike(allocatorAgent).call(
            inst.controller,
            abi.encodeWithSelector(IControllerLike.transferAsset_transfer.selector, USDC, recipient, 1_100_000e6)
        );
    }

}
