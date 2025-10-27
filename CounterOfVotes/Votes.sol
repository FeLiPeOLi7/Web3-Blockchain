// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Counter{
    uint256 public totalVotes;
    address public immutable ADMIN;
    mapping (address => bool) public voted;

    struct Proposal{
        string name;
        uint256 votes;
    }

    Proposal[] public proposals;

    enum Phase{
        Setup,
        Voting,
        Ended
    }

    Phase public phase;

    event Opened();
    event Voted(address indexed voter, uint256 indexed proposalId);
    event Closed();

    error AlreadyVoted();
    error PhaseError();
    error indexOutOfBounds();
    error NotAdmin();

    constructor(string[] memory names){
        ADMIN = msg.sender;
        for(uint i = 0; i < names.length; i++){
            proposals.push(Proposal({name: names[i], votes: 0}));
        }
        phase = Phase.Setup;
    }

    modifier onlyAdmin(){
        if(msg.sender != ADMIN){
            revert NotAdmin();
        }
        _;
    }

    modifier inPhase(Phase _phase){
        if(phase != _phase){
            revert PhaseError();
        }
        _;
    }

    function openVoting() external onlyAdmin inPhase(Phase.Setup) {
        phase = Phase.Voting;
        emit Opened();
    }

    function vote(uint256 index) external inPhase(Phase.Voting) {
        if (voted[msg.sender]) revert AlreadyVoted();
        if (index >= proposals.length) revert indexOutOfBounds();

        voted[msg.sender] = true; // registra primeiro (Effects)
        proposals[index].votes += 1; // depois altera votos
        emit Voted(msg.sender, index);
    }

    function closeVoting() external onlyAdmin inPhase(Phase.Voting) {
        phase = Phase.Ended;
        emit Closed();
    }

    function winner() external view inPhase(Phase.Ended) returns (uint256 idx) {
        uint256 max = 0;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (proposals[i].votes > max) {
                max = proposals[i].votes;
                idx = i;
            }
        }
    }

    function proposalsCount() external view returns (uint256) {
        return proposals.length;
    }
}

