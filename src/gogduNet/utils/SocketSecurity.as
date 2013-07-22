package gogduNet.utils
{
	/** 서버 클래스에서 허용 또는 비허용된 연결들의 목록을 가지는 클래스입니다.<p/>
	 * 여기서 허용되지 않거나 비허용된 연결의 클라이언트 측에선, 차단되어 연결이 끊겨도
	 * GogduNetEvent.CONNECT_FAIL 이벤트가 발생하지 않습니다.<p/>
	 * (즉, 연결을 경고나 알림 없이 바로 끊습니다)<p/>
	 * 
	 * (P2PClient에서만 특수하게, 객체에 추가할 Object 객체의 address 속성을 peerID로, port 속성을 음수로 설정해야 합니다.)
	 */
	public class SocketSecurity
	{
		private var _isPermission:Boolean;
		
		//{address, port}
		private var _sockets:Vector.<Object>;
		
		public function SocketSecurity(isPermission:Boolean, sockets:Vector.<Object>=null)
		{
			_isPermission = isPermission;
			
			if(sockets == null)
			{
				sockets = new Vector.<Object>();
			}
			_sockets = sockets;
		}
		
		/** 허용하는 목록인지 비허용하는 목록인지를 나타내는 값을 가져오거나 설정한다.
		 * true일 경우 이 객체의 목록들은 허용된 목록이며, false일 경우 이 객체의 목록들은
		 * 허용되지 않은 목록이 된다.
		 */
		public function get isPermission():Boolean
		{
			return _isPermission;
		}
		public function set isPermission(value:Boolean):void
		{
			_isPermission = value;
		}
		
		/** {address, port} address가 null이면 port만 일치해도 허용/비허용 대상, port가 음수면 address만 일치해도 허용/비허용 대상. 그러나 둘 다(address가 null이고 port가 음수)는 할 수 없다. */
		public function get sockets():Vector.<Object>
		{
			return _sockets;
		}
		public function set sockets(value:Vector.<Object>):void
		{
			_sockets = value;
		}
		
		public function addSocket(address:String, port:int):void
		{
			var i:int;
			for(i = 0; i < _sockets.length; i += 1)
			{
				if(_sockets[i])
				{
					if(_sockets[i].address == address && _sockets[i].port == port)
					{
						return;
					}
				}
			}
			
			_sockets.push({address:address, port:port});
		}
		
		public function removeSocket(address:String, port:int):void
		{
			var i:int;
			for(i = 0; i < _sockets.length; i += 1)
			{
				if(_sockets[i])
				{
					if(_sockets[i].address == address && _sockets[i].port == port)
					{
						_sockets.splice(i, 1);
					}
				}
			}
		}
		
		public function clear():void
		{
			_sockets.length = 0;
		}
		
		public function contain(address:String, port:int):Boolean
		{
			var i:int;
			for(i = 0; i < _sockets.length; i += 1)
			{
				if(_sockets[i])
				{
					//배열의 i번째의 address 속성이 null이거나 address 인자와 일치하는 경우
					if(!(_sockets[i].address) || _sockets[i].address == address)
					{
						//배열의 i번째의 port 속성이 음수거나 port 인자와 일치하는 경우
						if(_sockets[i].port < 0 || _sockets[i].port == port)
						{
							return true;
						}
					}
				}
			}
			
			return false;
		}
		
		public function dispose():void
		{
			_sockets = null;
		}
	}
}