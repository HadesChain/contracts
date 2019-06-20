pragma solidity 0.5.1;

interface Team {
    function refer(address name) external view returns (address);
}

/*
PoS+挖矿 智能合约
已开源至github
*/
contract miner{
    Team team = Team(address(0x6d943855aC3AC3205A5b2A95F7A41d3211de066f));
    uint256 cover;

    uint256 private rate = 1; // 收益为千一
    uint256 private base = 1000; // 同上
    uint256 private circle = 86400; // 收益日结
    mapping(address=>Card) private ledger; // 账户信息

    struct Card {
        uint256 chunked; // 历史收益
        uint256 profit; // 结算待取的收益
        uint256 fromtime; // 上次结息时间

        uint256 balance; // 历史投资
        uint256[] pool; // 矿池大小
        uint256 deep; // 享受奖励层级
        uint256 point; // 直推下级数量
        uint256[10] score; //邀请来挖矿数量 
    }

    event onBuy(
        address indexed customer,
        uint256 value,
        uint256 time
    );

    event onWithdraw(
        address indexed customer,
        uint256 value,
        uint256 time
    );

    event onBack(
        address indexed customer,
        uint256 chunk,
        uint256 time
    );
    
    // 初始化
    function()
        payable
        external
    {
    }
    
    // 购买矿机
    function buy()
        public
        payable
    {
        address customer = msg.sender;
        uint256 value = msg.value;
        
        require(status(customer)<=1); // 未开始状态或挖矿状态
        require(value >= 3000 ether); // 至少3000Ether
        
        require( (cover+value) <=194390000 ether); // 上限
        cover = SafeMath.add(cover,value);

        // 必须注册hid
        address refer = team.refer(customer);
        require(refer != address(0x00)); // 邀请人不为空

        bubble(customer , value, true , ledger[customer].fromtime==0);// 改变上9级

        liquid(customer); // 清算收益
        ledger[customer].fromtime = now; // 必须
        
        setPool(customer,value); // 重算矿池大小
        
        setDeep(customer); // 计算奖励深度
        setScore(customer); // 计算奖励算力.deep变化再执行更好,考虑执行频率,未优化

        emit onBuy(customer , value , now);
    }

    // 关闭矿机
    function close()
        public
    {
        address payable customer = msg.sender;
        
        require(status(customer)==1); // 挖矿状态
        _withdraw(customer);

        //计算可退算力
        uint256 _amount = calcRevert(customer);

        // 改变状态
        ledger[customer].balance = 0; // 设置close状态
        ledger[customer].deep = 0;
        ledger[customer].point = 0;
        ledger[customer].pool.length=0; // 清零

        if(_amount == 0) return; // 无可退算力
        else bubble(customer , _amount , false , true);

        _amount = SafeMath.div(_amount , 10);
        for(uint8 i=0; i<5; i+=1) {
            ledger[customer].score[i] = _amount;
            ledger[customer].score[i+5] = 0;
        }

        _amount = SafeMath.mul(_amount , 5);
        customer.transfer(_amount); // 给用户转一半的算力
        emit onBack(customer , _amount , now);
    }

    // 取收益,外部
    function withdraw() 
        public
    {
        address payable customer = msg.sender;
        
        require(status(customer)==1); // 挖矿状态
        _withdraw(customer);
    }

    // 取收益,内部
    function _withdraw(address payable customer)
        internal
    {     
        uint256 _oldrev = calcRevert(customer);
        liquid(customer); // 清算收益

        if(ledger[customer].profit>0) { // 如果有收益
            uint256 _profit = ledger[customer].profit;
            ledger[customer].profit=0;
            
            customer.transfer(_profit); // 给用户转币
            ledger[customer].chunked = SafeMath.add(ledger[customer].chunked,_profit);//登记历史收益
            emit onWithdraw(customer , _profit , now);

            uint256 _newrev = calcRevert(customer);
            if(_oldrev > _newrev) { // 如果可退算力发生减少
                bubble(customer , _oldrev-_newrev , false, false);
            }
        } 
    }

    // 取回算力
    function back() 
        public
    {
        address payable customer = msg.sender;
        require(status(customer)==2); // 退款状态

        require(now >= SafeMath.add(ledger[customer].fromtime , 30*circle)); // 一个月
        ledger[customer].fromtime = now;

        uint256 _amount;
        for(uint8 i=4; i>=0; i-=1) {
            if(ledger[customer].score[i]>0) {
                _amount = ledger[customer].score[i];
                ledger[customer].score[i] = 0;

                customer.transfer(_amount); // 取回算力
                emit onBack(customer , _amount , now);
                break;
            }
        }

    }

    // 统计函数,(挖矿速度/奖励速度/待领/  本金/已挖/ 状态
    function stats(address customer , uint256 seq)
        public
        view
        returns(uint256,uint256, uint256)
    {
        if(seq==1)
            return (ledger[customer].balance, ledger[customer].fromtime, ledger[customer].score[0] );
        else
            return (calcPow(customer), ledger[customer].chunked, profits(customer)+ledger[customer].profit);
    }

    // 返回当前状态
    function status(address customer)
        internal
        view
        returns (uint256)
    {
        if(ledger[customer].fromtime==0) {
            return 0; // 未开始
        }

        if(ledger[customer].balance>0) {
            return 1; // 挖矿中
        }

        if((ledger[customer].balance==0) && (ledger[customer].score[0]>0)) {
            return 2; // 关机,退款中
        }

        if(ledger[customer].balance==0 && ledger[customer].score[0]==0) {
            return 3; // 退款完成
        }
    }

    // 初买矿机/关矿机buy,close,影响上9级
    function bubble(address customer, uint256 amount, bool isIn, bool resetdeep) 
        internal
    {
        address refer = customer;
        uint256 _status;
        for(uint8 i=1; i<=9; i+=1) {
            refer = team.refer(refer);
            
            if(refer == address(0x00)) {// 已无上级,退出
                break;
            }
            
            _status = status(refer);

            // 矿机已关,跳过
            if(_status > 1 ) {    
                continue;
            }
            // 更新9层以内奖励记录
            if(isIn==true) ledger[refer].score[i] = SafeMath.add(ledger[refer].score[i] , amount);
            else  ledger[refer].score[i] = SafeMath.sub(ledger[refer].score[i] , amount);

            if(i==1 && resetdeep==true) { // 影响直属上级的级别, 增资或withdraw不影响deep
                if(isIn==true) ledger[refer].point = SafeMath.add(ledger[refer].point , 1);
                else ledger[refer].point = SafeMath.sub(ledger[refer].point , 1);

                if(_status == 1 ) setDeep(refer);
            }

            // 空用户,跳过
            if(_status == 0 ) {    
                continue;
            }

            // 上1层或deep以下层变化结算收益
            if(i==1 || i<=ledger[refer].deep ) {
                liquid(refer);
                setScore(refer);
            }         
        }
    }

    // 设置矿池大小
    function setPool(address customer , uint256 value)
        internal
    {  
        uint256 oldpool = calcPool(customer); // 旧池
        
        // 增加历史余额
        ledger[customer].balance = SafeMath.add(ledger[customer].balance, value);
        uint256 newpool = calcPool(customer); // 新池

        ledger[customer].pool.push( SafeMath.sub(newpool, SafeMath.add(oldpool , value)) );
        ledger[customer].pool.push(value);
    }

    // 设置奖励层数,按历史总投资额度计算
    function setDeep(address customer)
        internal
    {
        if(ledger[customer].balance>=27000 ether) {
            ledger[customer].deep = ledger[customer].point<9?ledger[customer].point:9;
        } else if(ledger[customer].balance>=9000 ether) {
            ledger[customer].deep = ledger[customer].point<6?ledger[customer].point:6;
        } else {
            ledger[customer].deep = ledger[customer].point<3?ledger[customer].point:3;
        }
    }

    // 设置推荐算力
    function setScore(address customer)
        internal
    {
        ledger[customer].score[0] = 0;
        for(uint8 i=1; i<= ledger[customer].deep; i+=1) {
            if(i==1) {
                ledger[customer].score[0] = SafeMath.add(ledger[customer].score[0] , ledger[customer].score[i]);
            } else {
                ledger[customer].score[0] = SafeMath.add(ledger[customer].score[0] , ledger[customer].score[i]/10);
            }
        }
    }

    // 计算总矿池,按历史总投资计算
    function calcPool(address customer)
        internal
        view
        returns (uint256)
    {
        if(ledger[customer].balance>=27000 ether) {
            return SafeMath.mul(ledger[customer].balance , 5);
        } else if(ledger[customer].balance>=9000 ether) {
            return SafeMath.mul(ledger[customer].balance , 4);
        } else {
            return SafeMath.mul(ledger[customer].balance , 3);
        }
    }
    // 算当前在挖算力,供liquid使用,已用js验证
    function calcPow(address customer) 
        internal
        view
        returns (uint256)
    {
        uint256 pow = 0;
        uint256 sum = 0;
        for(uint256 i=1; i<ledger[customer].pool.length; i+=2) {
            sum = sum + ledger[customer].pool[i-1] + ledger[customer].pool[i];
            if(sum > ledger[customer].chunked) {
                pow += ledger[customer].pool[i];
            }
        }

        return pow;
    }
    
    // 算当前可退算力,供close时使用,已用js验证
    function calcRevert(address customer) 
        internal
        view
        returns (uint256)
    {
        uint256 rev = 0;
        uint256 sum = 0;
        uint256 i = 0;
        for(i=0; i<ledger[customer].pool.length; i+=1) {

            sum = sum + ledger[customer].pool[i];
            if(rev == 0) {
                if(sum > ledger[customer].chunked) {
                    if(i%2==1) rev = sum - ledger[customer].chunked;
                    else rev = ledger[customer].pool[i+1];

                    i+=1;
                }
            } else {
                if(i%2==1) {
                    rev = rev + ledger[customer].pool[i];
                }
            }
        }

        return rev;
    }

    // 计算自身在挖算力+奖励总算力
    function calcBonus(address customer)
        internal
        view
        returns (uint256)
    { 
        if( ledger[customer].balance >=27000 ether) { // 奖励按历史总投资额度计算级别
            return ledger[customer].score[0];

        } else if(ledger[customer].balance >=9000 ether) {
            return ledger[customer].score[0]*8/10;

        } else {
            return ledger[customer].score[0]*6/10;
        }
    }
    

    // 结算收益
    function liquid(address customer)
        internal
    {  
        uint256 chunk = profits(customer); // 未结收益
        if(chunk==0) return;
        else ledger[customer].fromtime = (now - SafeMath.sub(now , ledger[customer].fromtime)%circle); // 结息时间

        ledger[customer].profit = SafeMath.add(ledger[customer].profit,chunk); // 结息
    }

    // 计算未结收益
    function profits(address customer)
        internal
        view
        returns (uint256)
    {
        if(status(customer) != 1) {
            return 0;
        }

        if(now<ledger[customer].fromtime+circle) {
            return 0;
        }

        uint256 day = SafeMath.sub(now , ledger[customer].fromtime);
        day = SafeMath.div(day , circle);

        //计算未结的收益
        uint256 unprofit = SafeMath.mul(SafeMath.add(calcPow(customer),calcBonus(customer))/base, SafeMath.mul(day , rate) );
        
        // 不超过矿池上限
        uint256 poolLimit = calcPool(customer);
        uint256 payed = SafeMath.add(ledger[customer].chunked , ledger[customer].profit);

        if(SafeMath.add(payed,unprofit) > poolLimit) {
            unprofit = SafeMath.sub(poolLimit , payed);
        }

        return unprofit; 
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