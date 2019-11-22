pragma solidity ^0.4.25;

interface Team {
    function reg(uint256 code) external;
    function refer(address name) external view returns (address);
    function getAddr(uint256 id) external view returns(address);
}

contract LotteryTeam is Team {
    // user=>refer
    uint256 internal sn = 112388; 
    
    mapping(uint256 => address) internal IdToAddr;
    mapping(address => uint256) internal AddrToId;

    mapping(address => address) internal agents;

    modifier antiScam(uint256 code) {
        require(agents[msg.sender] == address(0x00));//用户未登记过
        
        address refer = getAddr(code); // 邀请者地址
        require(refer != address(0x00)); // 邀请者须为真
        
        require(refer != msg.sender); // 邀请者不是自己
        require(agents[refer] != msg.sender); // 不能互为邀请者
        _;
    }

    constructor () public {
        IdToAddr[sn] = msg.sender;
        AddrToId[msg.sender] = sn;
        agents[msg.sender] = address(0x00);
        sn += 1;
    }

    // be agent
    function reg(uint256 code)
        antiScam(code)
        public
    {
        agents[msg.sender] = getAddr(code);
        
        IdToAddr[sn] = msg.sender;
        AddrToId[msg.sender] = sn;
        
        sn+=1;
    }


    // 获取代理账户信息
    function refer(address name)
        public
        view
        returns (address)
    {
        return agents[name];
    }


    function getAddr(uint256 id)
        public
        view
        returns (address)
    {
        return IdToAddr[id];
    }

    function getId(address addr)
        public
        view
        returns (uint256)
    {
        return AddrToId[addr];
    }

}