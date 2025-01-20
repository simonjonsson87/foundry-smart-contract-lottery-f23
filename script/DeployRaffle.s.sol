// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";
import {console} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract DeployRaffle is Script {
    function run() external {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        AddConsumer addConsumer = new AddConsumer();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfigByChainId(block.chainid);
        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscription.createSubscription(config.vrfCoordinator, config.account);

            helperConfig.setConfig(block.chainid, config);
        }

        VRFCoordinatorV2_5Mock coordinator = VRFCoordinatorV2_5Mock(config.vrfCoordinator);
        (uint96 balance,,,,) = coordinator.getSubscription(config.subscriptionId);
        if (balance == 0) {
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        vm.startBroadcast();
        Raffle raffle = new Raffle(
            config.gasLane,
            config.callbackGasLimit,
            config.subscriptionId,
            config.interval,
            config.entranceFee,
            config.vrfCoordinator
        );
        vm.stopBroadcast();

        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }
}
