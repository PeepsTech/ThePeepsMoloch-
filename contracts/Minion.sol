pragma solidity ^0.6.0;

import "./PeepsDAO.sol";

contract Minion {

    string public constant MINION_ACTION_DETAILS = '{"isMinion": true, "title":"MINION", "description":"';

    PeepsMoloch public peepsmolochs;
    address public peepsmolochApprovedToken;
    mapping (uint256 => Action) public actions; // proposalId => Action

    struct Action {
        uint256 value;
        address to;
        address proposer;
        bool executed;
        bytes data;
    }

    event ActionProposed(uint256 proposalId, address proposer);
    event ActionExecuted(uint256 proposalId, address executor);

    constructor(address _peepsmoloch) public {
        peepsmolochs = PeepsMoloch(_peepsmoloch);
        peepsmolochApprovedToken = peepsmolochs.depositToken();
    }

    // withdraw funds from the moloch
    function doWithdraw(address _token, uint256 _amount) public {
        peepsmolochs.withdrawBalance(_token, _amount);
    }

    function proposeAction(
        address _actionTo,
        uint256 _actionValue,
        bytes memory _actionData,
        string memory _description
    )
        public
        returns (uint256)
    {
        // No calls to zero address allows us to check that Minion submitted
        // the proposal without getting the proposal struct from the moloch
        require(_actionTo != address(0), "Minion::invalid _actionTo");

        string memory details = string(abi.encodePacked(MINION_ACTION_DETAILS, _description, '"}'));

        uint256 proposalId = peepsmolochs.submitProposal(
            address(this),
            0,
            0,
            peepsmolochApprovedToken,
            0,
            peepsmolochApprovedToken,
            details
        );

        Action memory action = Action({
            value: _actionValue,
            to: _actionTo,
            proposer: msg.sender,
            executed: false,
            data: _actionData
        });

        actions[proposalId] = action;

        emit ActionProposed(proposalId, msg.sender);
        return proposalId;
    }

    function executeAction(uint256 _proposalId) public returns (bytes memory) {
        Action memory action = actions[_proposalId];
        bool[5] memory flags = peepsmolochs.getProposalFlags(_proposalId);

        // minion did not submit this proposal
        require(action.to != address(0), "Minion::invalid _proposalId");
        // can't call arbitrary functions on parent moloch
        require(action.to != address(peepsmolochs), "Minion::invalid target");
        require(!action.executed, "Minion::action executed");
        require(address(this).balance >= action.value, "Minion::insufficient eth");
        require(flags[2], "Minion::proposal not passed");

        // execute call
        actions[_proposalId].executed = true;
        (bool success, bytes memory retData) = action.to.call.value(action.value)(action.data);
        require(success, "Minion::call failure");
        emit ActionExecuted(_proposalId, msg.sender);
        return retData;
    }

    fallback() external payable { }
}