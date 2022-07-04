// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0 ;

interface ILedger {
    function updateNodes(address[] memory _nodeAddrs) external;
    function updateLedger(
        address[] calldata _userAddrs, 
        uint256[] calldata _nonces,
        address[] calldata _tokenAddrs, 
        uint256[] calldata _amounts,
        string[] calldata _txHashs
    )  external;
}

abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

contract Ledger is Initializable, ILedger{
    using SafeMath for uint256;   
    address[] nodeAddrList;
    mapping(address => bool) public nodeAddrSta;
    mapping(uint256 => NodeMsg) nodeMsg;
    uint256 num;  
    mapping(uint256 => mapping(address => bool)) status;
    uint256 ledgerNum; 
    mapping(uint256 => LedgerMsg)  ledgerIndex;
    mapping(address => mapping(uint256 => uint256)) ledgerMsg;

    event UpdateNodeAddr(address[] nodeAddrs); 
    event UpdateLedger(address userAddr, uint256 nonce, address token, uint256 amount, string txHash); 
    event UpdateLedgerFail(address userAddr, uint256 nonce, address token, uint256 amount, string txHash); 
    
    struct NodeMsg {
        uint256  nodeNum;
        uint256  nodeVoteNum;
        mapping(address => uint256) nodeAddrIndex;
        mapping(uint256 => address) nodeIndexAddr;
        mapping(address => uint256) nodeAddrVotes;
        mapping(address => bool) addrSta;
        address[] voteAddrList;
    }

    struct DataMsg{
        address token;                        
        uint256 amount;
        string txHash;
    }

    struct LedgerMsg{
        uint256  nodeVoteNum;
        mapping(uint256 => DataMsg)  dataFlag;
        uint256  dataFlagNum;
        mapping(uint256 => uint256) dataFlagIndex;
        mapping(uint256 => uint256) dataIndexFlag;
        mapping(uint256 => uint256) dataVotes;
        mapping(address => bool) addrSta;
        address[] voteAddrList;          
        bool  consensusSta;       
    }

    function init(address[] memory _nodeAddrs) external initializer{
        __Ledger_init_unchained(_nodeAddrs);
    }

    function __Ledger_init_unchained(address[] memory _nodeAddrs) internal initializer{
        for (uint256 i = 0; i< _nodeAddrs.length; i++){
            nodeAddrList.push(_nodeAddrs[i]);
            nodeAddrSta[_nodeAddrs[i]] = true;
        }
    }
 
    fallback() external{

    }
    
    function updateLedger(
        address[] calldata _userAddrs, 
        uint256[] calldata _nonces,
        address[] calldata _tokenAddrs, 
        uint256[] calldata _amounts,
        string[] calldata _txHashs
    ) override external {
        address _sender = msg.sender;
        uint256 len = _userAddrs.length;
        require(len == _nonces.length, "Number of parameters does not match"); 
        require(_nonces.length == _tokenAddrs.length, "Number of parameters does not match"); 
        require(_tokenAddrs.length == _amounts.length , "Number of parameters does not match"); 
        require(_txHashs.length == _amounts.length , "Number of parameters does not match"); 
        require(nodeAddrSta[_sender], "The caller is not the nodeAddr"); 
        for (uint256 i=0; i < len; i++){
             _updatLedger(_userAddrs[i],_nonces[i],_tokenAddrs[i],_amounts[i],_txHashs[i],_sender);
        }
    }

    function updateNodes(address[] calldata _nodeAddrs) override external{
        address _sender = msg.sender;
        uint256 time = block.timestamp%86400;
        uint256 day = block.timestamp/86400;
        require(time >= 75600 && time <= 79200, "The call time is not within the specified range"); 
        require(nodeAddrSta[_sender], "The caller is not the nodeAddr"); 
        _verfyNodes(_nodeAddrs);
        _updatNodeAddr(day, _nodeAddrs, _sender);
    }

    function _updatLedger(
        address _userAddr, 
        uint256 _nonce,
        address _tokenAddr, 
        uint256 _amount,
        string memory _txHash,
        address _sender
    ) internal{
        uint256 _ledgerNum = ledgerMsg[_userAddr][_nonce];
        LedgerMsg storage _ledgerMsg = ledgerIndex[_ledgerNum];
        if(_ledgerNum == 0){
            _ledgerNum = ++ledgerNum;
            _ledgerMsg = ledgerIndex[_ledgerNum];
            ledgerMsg[_userAddr][_nonce] = _ledgerNum;
        }
        require(!_ledgerMsg.addrSta[_sender], "The node address has already been voted"); 
        _ledgerMsg.addrSta[_sender] = true;
        _ledgerMsg.voteAddrList.push(_sender);
        if(!_ledgerMsg.consensusSta){
            bytes32 _dataFlagHash = keccak256(abi.encode(_tokenAddr, _amount, _txHash));
            uint256 _dataFlag = bytes32ToUint(_dataFlagHash);
            DataMsg memory _dataMsg = DataMsg(_tokenAddr, _amount, _txHash);
            uint256 _dataFlagIndex = _ledgerMsg.dataFlagIndex[_dataFlag];
            if (_dataFlagIndex == 0){
                _dataFlagIndex = ++_ledgerMsg.dataFlagNum;
                _ledgerMsg.dataFlagIndex[_dataFlag] = _dataFlagIndex;
                _ledgerMsg.dataIndexFlag[_dataFlagIndex] = _dataFlag;
                _ledgerMsg.dataFlag[_dataFlag] = _dataMsg;
            }
            _ledgerMsg.dataVotes[_dataFlag]++;
            uint256 _nodeVoteNum = ++_ledgerMsg.nodeVoteNum;
            if(_nodeVoteNum > 6){
                _dataRank(_userAddr, _nonce, _ledgerMsg);
            }
        }
    }

    function _dataRank(address _userAddr, uint256 _nonce, LedgerMsg storage _ledgerMsg) internal {
        uint256 _dataFlagNum = _ledgerMsg.dataFlagNum;
        for (uint256 i=1; i <= _dataFlagNum; i++){
            for (uint256 j=i+1 ; j <= _dataFlagNum; j++){
                uint256 nextData = _ledgerMsg.dataIndexFlag[j];
                uint256 prefixData = _ledgerMsg.dataIndexFlag[i];
                if (_ledgerMsg.dataVotes[prefixData] < _ledgerMsg.dataVotes[nextData]){
                    _ledgerMsg.dataFlagIndex[prefixData] = j;
                    _ledgerMsg.dataFlagIndex[nextData] = i;
                    _ledgerMsg.dataIndexFlag[i] = nextData;
                    _ledgerMsg.dataIndexFlag[j] = prefixData;
                }
            }
        }
        uint256 _dataFlag = _ledgerMsg.dataIndexFlag[1];
        DataMsg memory _dataMsg = _ledgerMsg.dataFlag[_dataFlag];
        if(_ledgerMsg.dataVotes[_dataFlag] > 6){
            _ledgerMsg.consensusSta = true;
            emit UpdateLedger(_userAddr, _nonce, _dataMsg.token, _dataMsg.amount, _dataMsg.txHash);
        }else if(_ledgerMsg.nodeVoteNum > 8){
            uint256 _ledgerNum = ++ledgerNum;
            ledgerMsg[_userAddr][_nonce] = _ledgerNum;
            emit UpdateLedgerFail(_userAddr, _nonce, _dataMsg.token, _dataMsg.amount, _dataMsg.txHash);
        }
    }

    function _updatNodeAddr(uint256 _day, address[] calldata _nodeAddrs, address _sender) internal{
        NodeMsg storage _nodeMsg = nodeMsg[_day];
        require(!_nodeMsg.addrSta[_sender], "The node address has already been voted"); 
        _nodeMsg.addrSta[_sender] = true;
        for (uint256 i = 0; i< _nodeAddrs.length; i++){
            address _nodeAddr = _nodeAddrs[i];
            uint256 _nodeAddrIndex = _nodeMsg.nodeAddrIndex[_nodeAddr];
            if (_nodeAddrIndex == 0){
                _nodeAddrIndex = ++_nodeMsg.nodeNum;
                _nodeMsg.nodeAddrIndex[_nodeAddr] = _nodeAddrIndex;
                _nodeMsg.nodeIndexAddr[_nodeAddrIndex] = _nodeAddr;
            }
            _nodeMsg.nodeAddrVotes[_nodeAddr]++;
        }
        uint256 _nodeVoteNum = ++_nodeMsg.nodeVoteNum;
        _nodeMsg.voteAddrList.push(_sender);
        if(_nodeVoteNum > 6){
            _nodeRank(_nodeMsg);
        }
    }

    function _nodeRank(NodeMsg storage _nodeMsg) internal {
        uint256 _nodeNum = _nodeMsg.nodeNum;
        for (uint256 i=1; i <= _nodeNum; i++){
            for (uint256 j=i+1 ; j <= _nodeNum; j++){
                address nextAddr = _nodeMsg.nodeIndexAddr[j];
                address prefixAddr = _nodeMsg.nodeIndexAddr[i];
                if (_nodeMsg.nodeAddrVotes[prefixAddr] < _nodeMsg.nodeAddrVotes[nextAddr]){
                    _nodeMsg.nodeAddrIndex[prefixAddr] = j;
                    _nodeMsg.nodeAddrIndex[nextAddr] = i;
                    _nodeMsg.nodeIndexAddr[i] = nextAddr;
                    _nodeMsg.nodeIndexAddr[j] = prefixAddr;
                }
            }
        }
        for (uint256 i=0; i < nodeAddrList.length; i++){
            nodeAddrSta[nodeAddrList[i]] = false;
        }
        delete nodeAddrList;
        for (uint256 i=1; i < 12; i++){
            nodeAddrList.push(_nodeMsg.nodeIndexAddr[i]);
            nodeAddrSta[_nodeMsg.nodeIndexAddr[i]] = true;
        }
        emit UpdateNodeAddr(nodeAddrList);
    }

    function _verfyNodes(address[] memory _nodeAddrs) internal {
        require(_nodeAddrs.length ==11, "The number of nodes must be 11"); 
        uint256 _num= num++;
        for(uint i= 0; i<_nodeAddrs.length; i++){
            require(!status[_num][_nodeAddrs[i]], "A node can only submit once"); 
            status[_num][_nodeAddrs[i]] = true;
        }
    }

    function bytes32ToUint(bytes32 b) public pure returns (uint256){
        uint256 number;
        for(uint i= 0; i<b.length; i++){
            number = number + uint8(b[i])*(2**(8*(b.length-(i+1))));
        }
        return  number;
    }

    function queryVotes(address userAddr, uint256 nonce) 
        external 
        view 
        returns(
            bool,
            uint256,
            address[] memory, 
            address,
            uint256, 
            string memory,
            uint256)
    {
        uint256 _ledgerNum = ledgerMsg[userAddr][nonce];
        LedgerMsg storage _ledgerMsg = ledgerIndex[_ledgerNum];
        uint256 _dataFlag = _ledgerMsg.dataIndexFlag[1];
        DataMsg memory _dataMsg = _ledgerMsg.dataFlag[_dataFlag];
        uint256 _dataVotes = _ledgerMsg.dataVotes[_dataFlag];
        return (_ledgerMsg.consensusSta, _ledgerMsg.nodeVoteNum, _ledgerMsg.voteAddrList, _dataMsg.token, _dataMsg.amount, _dataMsg.txHash,_dataVotes);
    }

    function queryVoteNodes(uint256 _day)  external view returns(address[] memory){
        uint256 calDay = block.timestamp/86400;
        _day = calDay.sub(_day).add(1);
        NodeMsg storage _nodeMsg = nodeMsg[_day];
        return _nodeMsg.voteAddrList;
    }

    function queryNodes() external view returns(address[] memory){
        address[] memory nodes = new address[](11);
        if(nodeAddrList.length > 0){
            for (uint256 i = 0; i < 11; i++) {
                nodes[i] = nodeAddrList[i];
            }
        }
        return nodes;
    }
}
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
