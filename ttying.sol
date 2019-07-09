pragma solidity 0.5.1;

/*
天天盈-活期理财 智能合约
已开源至github
*/
contract ttying{
    uint256 private rate = 4; // 收益为万四
    uint256 private base = 10000; // 同上
    uint256 private circle = 86400; // 利息日结
    mapping(address=>card) private ledger; // 账户信息

    struct card {
        uint256 profit; // 已结利润
        uint256 balance; // 账户余额
        uint256 chunked; // 历史收益
        uint256 fromtime; // 上次结息时间
    }

    event onDeposit(
        address indexed customer,
        uint256 value,
        uint256 time
    );

    event onWithdraw(
        address indexed customer,
        uint256 value,
        uint256 time
    );

    event onLiquid(
        address indexed customer,
        uint256 chunk,
        uint256 time
    );

    // 存款函数
    function deposit()
        public
        payable
    {
        address customer = msg.sender;
        uint256 value = msg.value;
        require(value > 0);
        
        liquid(customer); // 清算利息
        ledger[customer].balance = SafeMath.add(ledger[customer].balance, value); // 增加余额

        emit onDeposit(customer , value , now);
    }

    // 取款函数
    function withdraw(uint256 amount)
        public
    {
        address payable customer = msg.sender;
        require(amount > 0);
        require(ledger[customer].balance+profits(customer)>=amount);
        
        liquid(customer); // 清算利息

        if(ledger[customer].profit>=amount) { // 如果取款额度<=利息
            ledger[customer].profit -= amount;
        } else { // 如果取款额度>利息
            uint256 _profit = ledger[customer].profit;
            ledger[customer].profit = 0;
            ledger[customer].balance = SafeMath.sub(ledger[customer].balance, SafeMath.sub(amount,_profit));
        }

        customer.transfer(amount); // 给用户转币
        emit onWithdraw(customer , amount , now);
    }

    // 统计函数,统计历史收益,当前收益,本金,上次结息时间
    function stats(address customer)
        public
        view
        returns(uint256,uint256, uint256,uint256)
    {
        return (ledger[customer].chunked , profits(customer), ledger[customer].balance, ledger[customer].fromtime);
    }

    // 结算利息
    function liquid(address customer)
        internal
    {
        
        uint256 chunk = calc(customer); // 未结利息
        ledger[customer].fromtime = now; // 结息时间
        
        if(chunk==0) return;
        ledger[customer].chunked = SafeMath.add(ledger[customer].chunked,chunk);//历史收益
        ledger[customer].profit = SafeMath.add(ledger[customer].profit,chunk); // 结息
        emit onLiquid(customer, chunk, now);
    }

    // 计算利息(含已结+未结)
    function profits(address customer)
        internal
        view
        returns (uint256)
    {
        return SafeMath.add(ledger[customer].profit , calc(customer));
    }

    // 计算未结利息
    function calc(address customer)
        internal
        view
        returns (uint256)
    {
        if(ledger[customer].balance == 0 || ledger[customer].fromtime == 0) {
            return 0;
        }

        uint256 day = SafeMath.sub(now , ledger[customer].fromtime);
        day = SafeMath.div(day , circle);

        return SafeMath.mul(ledger[customer].balance/base, SafeMath.mul(day , rate) ); // 计算未结的利息
    }
}

library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
}