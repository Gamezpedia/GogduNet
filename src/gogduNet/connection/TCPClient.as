package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.net.Socket;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	
	import gogduNet.events.DataEvent;
	import gogduNet.events.GogduNetEvent;
	import gogduNet.utils.Base64;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.cloneByteArray;
	import gogduNet.utils.spliceByteArray;
	
	/** 연결이 성공한 경우 발생합니다. */
	[Event(name="connect", type="gogduNet.events.GogduNetEvent")]
	/** 서버 등에 의해 비자발적으로 연결이 끊긴 경우 발생. (close() 함수로는 발생하지 않는다.) */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** <p>데이터를 수신하면 발생.</p>
	 * <p>(이벤트의 data 속성은 수신한 데이터의 바이트 배열이며, 패킷 단위로 구분되지 않습니다.)</p>
	 * <p>(dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="dataCome", type="gogduNet.events.DataEvent")]
	/** <p>정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.</p>
	 * <p>(dataType, dataDefinition, data)</p>
	 */
	[Event(name="dataReceive", type="gogduNet.events.DataEvent")]
	/** <p>정상적이지 않은 데이터를 수신했을 때 발생</p>
	 * <p>(dataType:DataType.INVALID, dataDefinition:DataDefinition.INVALID, data:데이터의 ByteArray)</p>
	 */
	[Event(name="invalidData", type="gogduNet.events.DataEvent")]
	/** <p>연결 시도가 실패한 경우 발생한다.<p/>
	 * <p/>( data:실패한 이유(IOErrorEvent.IO_ERROR or SecurityErrorEvent.SECURITY_ERROR or "Timeout" or "Saturation") )</p>
	 * <p>IOErrorEvent.IO_ERROR : IO_ERROR로 연결 실패</p>
	 * <p>SecurityErrorEvent.SECURITY_ERROR : SECURITY_ERROR로 연결 실패</p>
	 * <p>"Timeout" : 연결 시간 초과</p>
	 * <p>"Saturation" : 서버측 최대 인원 초과</p>
	 */
	[Event(name="connectFail", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	
	/** @langversion 3.0
	 * @playerversion Flash Player 11
	 * @playerversion AIR 3.0
	 */
	public class TCPClient extends ClientBase
	{
		/** 내부적으로 연결 검사를 위해 사용되는 타이머 */
		private var _timer:Timer;
		/** 패킷을 뭉쳐서 보내는 간격을 재는 타이머 */
		private var _unitedSendingTimer:Timer;
		
		/** 통신 응답 경과 한계 */
		private var _idleTimeoutLimit:Number;
		
		/** 서버와 마지막으로 통신한 시각(정확히는 마지막으로 서버로부터 정보를 전송 받은 시각) */
		private var _lastReceivedTime:Number;
		
		/** 네이티브 소켓 */
		private var _socket:Socket;
		/** 연결할 서버의 address */
		private var _serverAddress:String;
		/** 연결할 서버의 포트 */
		private var _serverPort:int;
		
		/** 현재 연결되어 있는가를 나타내는 bool 값 */
		private var _isConnected:Boolean;
		/** 연결된 지점의 시간을 나타내는 변수 */
		private var _connectedTime:Number;
		/** 디버그용 기록 */
		private var _record:RecordConsole;
		
		/** 수신되었으나 아직 처리되지 않은 데이터들을 임시로 저장해 두는 바이트 배열 */
		private var _backupBuffer:ByteArray;
		/** 패킷을 한 번에 뭉쳐서 보내기 위해 사용되는 배열 버퍼. */
		private var _unitedBuffer:Vector.<Object>;
		
		/** GogduNetEvent.CONNECTION_UPDATE 이벤트 객체 */
		private var _event:GogduNetEvent;
		
		/** <p>serverAddress : 연결할 서버의 address</p>
		 * <p>serverPort : 연결할 서버의 포트</p>
		 */
		public function TCPClient(serverAddress:String, serverPort:int=0)
		{
			_timer = new Timer( 60000 / 5 );
			_unitedSendingTimer = new Timer(100);
			
			_idleTimeoutLimit = 60000;
			_lastReceivedTime = -1;
			
			_socket = new Socket();
			_serverAddress = serverAddress;
			_serverPort = serverPort;
			
			_isConnected = false;
			_connectedTime = -1;
			
			_record = new RecordConsole();
			
			_backupBuffer = new ByteArray();
			_unitedBuffer = new <Object>[];
			
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
		}
		
		/** <p>통신 응답 경과 한계 시간을 가져오거나 설정한다.(ms)</p>
		 * <p>이 시간을 넘도록 정보가 수신되지 않은 경우엔 연결이 끊긴 것으로 간주하고 이쪽에서도 연결을 끊는다.</p>
		 * <p>기본값은 60000</p>
		 */
		public function get idleTimeoutLimit():Number
		{
			return _idleTimeoutLimit;
		}
		public function set idleTimeoutLimit(value:Number):void
		{
			_idleTimeoutLimit = value;
			_timer.delay = _idleTimeoutLimit / 5;
		}
		
		/** 패킷을 뭉쳐서 보내는 간격을 가져오거나 설정한다.(ms) 기본값은 100. */
		public function get unitedSendingInterval():Number
		{
			return _unitedSendingTimer.delay;
		}
		public function set unitedSendingInterval(value:Number):void
		{
			_unitedSendingTimer.delay = value;
		}
		
		/** 플래시 네이티브 소켓을 가져온다. */
		public function get socket():Socket
		{
			return _socket;
		}
		
		/** 연결할 서버의 address를 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
		public function get serverAddress():String
		{
			return _serverAddress;
		}
		public function set serverAddress(value:String):void
		{
			if(_isConnected == true)
			{
				return;
			}
			
			_serverAddress = value;
		}
		
		/** 연결할 서버의 포트를 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
		public function get serverPort():int
		{
			return _serverPort;
		}
		public function set serverPort(value:int):void
		{
			if(_isConnected == true)
			{
				return;
			}
			
			_serverPort = value;
		}
		
		/** 현재 연결되어 있는가를 나타내는 값을 가져온다. */
		public function get isConnected():Boolean
		{
			return _isConnected;
		}
		
		/** 디버그용 기록을 가지고 있는 RecordConsole 객체를 가져온다. */
		public function get record():RecordConsole
		{
			return _record;
		}
		
		/** 연결된 후 시간이 얼마나 지났는지를 나타내는 Number 값을 가져온다.(ms) */
		public function get elapsedTimeAfterConnected():Number
		{
			if(_isConnected == false)
			{
				return -1;
			}
			
			return getTimer() - _connectedTime;
		}
		
		/** 마지막으로 연결된 시각으로부터 지난 시간을 가져온다.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** 마지막으로 연결된 시각을 갱신한다.
		 * (서버에게서 정보가 들어온 경우 자동으로 이 함수가 실행되어 갱신된다.)
		 */
		public function updateLastReceivedTime():void
		{
			_lastReceivedTime = getTimer();
			dispatchEvent(_event);
		}
		
		public function dispose():void
		{
			_socket.close();
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			_socket.removeEventListener(Event.CLOSE, _socketClosed);
			_socket.removeEventListener(ProgressEvent.SOCKET_DATA, _listen);
			
			this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveConnectPacket);
			this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveUnitedPacket);
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _checkConnection);
			_timer = null;
			
			_unitedSendingTimer.removeEventListener(TimerEvent.TIMER, _unitedSend);
			_unitedSendingTimer.stop();
			_unitedSendingTimer = null;
			
			_socket = null;
			_serverAddress = null;
			
			_record.dispose();
			_record = null;
			
			_backupBuffer = null;
			_unitedBuffer = null;
			
			_event = null;
			
			_isConnected = false;
		}
		
		/** 서버와의 연결을 시도한다. */
		public function connect():void
		{
			if(!_serverAddress || _isConnected == true)
			{
				return;
			}
			
			_socket.connect(_serverAddress, _serverPort);
			_socket.addEventListener(Event.CONNECT, _socketConnect);
			_socket.addEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
		}
		
		private function _socketConnect(e:Event):void
		{
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			
			_socket.addEventListener(ProgressEvent.SOCKET_DATA, _listen);
			
			updateLastReceivedTime();
			
			_record.addRecord(true, "(Before validate)Connected to server");
			
			_timer.addEventListener(TimerEvent.TIMER, _checkConnection);
			_timer.start();
			
			this.addEventListener(DataEvent.DATA_RECEIVE, _receiveConnectPacket);
			
			setTimeout(_failReceiveConnectPacket, 10000);
		}
		
		private function _receiveConnectPacket(e:DataEvent):void
		{
			if(e.dataType == DataType.SYSTEM)
			{
				if(e.dataDefinition == DataDefinition.CONNECT_SUCCESS)
				{
					this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveConnectPacket);
					
					this.addEventListener(DataEvent.DATA_RECEIVE, _receiveUnitedPacket);
					
					_connectedTime = getTimer();
					
					_unitedSendingTimer.addEventListener(TimerEvent.TIMER, _unitedSend);
					_unitedSendingTimer.start();
					
					_record.addRecord(true, "(After validate)Connected to server(connectedTime:" + _connectedTime + ")");
					
					_socket.addEventListener(Event.CLOSE, _socketClosed);
					_isConnected = true;
					
					dispatchEvent(new GogduNetEvent(GogduNetEvent.CONNECT));
				}
				else if(e.dataDefinition == DataDefinition.CONNECT_FAIL)
				{
					_close();
					this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveConnectPacket);
					
					_record.addRecord(true, "Failed connect to server(Saturation)");
					
					dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, "Saturation") );
				}
			}
		}
		
		private function _failReceiveConnectPacket():void
		{
			try
			{
				if(_isConnected == false)
				{
					_close();
					this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveConnectPacket);
					
					_record.addRecord(true, "Failed connect to server(Timeout)");
					
					dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, "Timeout") );
				}
			}
			catch(e:Error)
			{
			}
		}
		
		/** IOErrorEvent.IO_ERROR로 연결이 실패 */
		private function _socketConnectFail(e:IOErrorEvent):void
		{
			_close();
			
			_record.addRecord(true, "Failed connect to server(IOErrorEvent)");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, null) );
		}
		
		/** SecurityErrorEvent.SECURITY_ERROR로 연결이 실패 */
		private function _socketConnectFail2(e:SecurityErrorEvent):void
		{
			_close();
			
			_record.addRecord(true, "Failed connect to server(SecurityErrorEvent)");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, null) );
		}
		
		/** <p>서버와의 연결을 끊는다.</p>
		 * <p>(네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)</p>
		 */
		public function close():void
		{
			if(_isConnected == false)
			{
				return;
			}
			
			_record.addRecord(true, "Connection to close(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
			
			_close();
		}
		
		private function _close():void
		{
			_socket.close();
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			_socket.removeEventListener(Event.CLOSE, _socketClosed);
			_socket.removeEventListener(ProgressEvent.SOCKET_DATA, _listen);
			
			this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveConnectPacket);
			this.removeEventListener(DataEvent.DATA_RECEIVE, _receiveUnitedPacket);
			
			_timer.removeEventListener(TimerEvent.TIMER, _checkConnection);
			_timer.stop();
			
			_unitedSendingTimer.removeEventListener(TimerEvent.TIMER, _unitedSend);
			_unitedSendingTimer.stop();
			
			_backupBuffer.clear();
			_unitedBuffer.length = 0;
			
			_isConnected = false;
		}
		
		private function _sendData(type:uint, definition:uint, data:ByteArray, unity:Boolean):Boolean
		{
			if(unity == true)
			{
				var node:Object = UnitedPacketNode.create(type, definition, data);
				_unitedBuffer.push(node);
				return true;
			}
			else
			{
				var packet:ByteArray = Packet.create(type, definition, data);
				if(packet == null){return false;}
				
				_socket.writeBytes(packet, 0);
				_socket.flush();
				return true;
			}
			
			return false;
		}
		
		private function _sendSystemData(definition:uint, data:ByteArray, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendData(DataType.SYSTEM, definition, data, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDefinition(definition:uint, data:Boolean, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendData(DataType.DEFINITION, definition, null, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBoolean(definition:uint, data:Boolean, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeBoolean(data);
			
			return _sendData(DataType.BOOLEAN, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendByte(definition:uint, data:int, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(DataType.BYTE, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedByte(definition:uint, data:uint, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeByte(data);
			
			return _sendData(DataType.UNSIGNED_BYTE, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendShort(definition:uint, data:int, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(DataType.SHORT, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedShort(definition:uint, data:uint, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeShort(data);
			
			return _sendData(DataType.UNSIGNED_SHORT, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendInt(definition:uint, data:int, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeInt(data);
			
			return _sendData(DataType.INT, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendUnsignedInt(definition:uint, data:uint, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeUnsignedInt(data);
			
			return _sendData(DataType.UNSIGNED_INT, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendFloat(definition:uint, data:Number, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeFloat(data);
			
			return _sendData(DataType.FLOAT, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendDouble(definition:uint, data:Number, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeDouble(data);
			
			return _sendData(DataType.DOUBLE, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendBytes(definition:uint, data:ByteArray, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			return _sendData(DataType.BYTES, definition, data, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendString(definition:uint, data:String, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(data, EncodingFormat.encoding);
			
			return _sendData(DataType.STRING, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendArray(definition:uint, data:Array, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(DataType.ARRAY, definition, bytes, unity);
		}
		
		/** <p>서버로 데이터를 전송한다.</p>
		 * <p>unity 인자를 true로 설정하면 패킷을 바로 보내지 않고 잠시 뒤에 다른 패킷과
		 * 함께 뭉쳐서 보내며, 데이터 사용량을 줄일 수 있습니다.</p>
		 * <p>패킷 형식이 맞지 않거나 연결되지 않은 등의 이유로 전송이 실패하면 false를, 그 외엔 true를 반환한다.</p>
		 */
		public function sendObject(definition:uint, data:Object, unity:Boolean=false):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = JSON.stringify(data);
			
			var bytes:ByteArray = new ByteArray();
			bytes.writeMultiByte(str, EncodingFormat.encoding);
			
			return _sendData(DataType.OBJECT, definition, bytes, unity);
		}
		
		private function _socketClosed(e:Event):void
		{
			_record.addRecord(true, "Connection to server is disconnected(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
			
			_close();
			
			dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
		}
		
		/** 뭉친 패킷 수신 */
		private function _receiveUnitedPacket(e:DataEvent):void
		{
			if(e.dataType == DataType.SYSTEM)
			{
				if(e.dataDefinition == DataDefinition.UNITED_PACKET)
				{
					var bytes:ByteArray = e.data as ByteArray;
					bytes.position = 0;
					
					try{var str:String = bytes.readMultiByte(bytes.length, EncodingFormat.encoding);}
					catch(e:Error)
					{
						dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, bytes) );
						return;
					}
					
					try{var array:Array = JSON.parse(str) as Array;}
					catch(e:Error)
					{
						dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, bytes) );
						return;
					}
					
					var i:uint;
					for(i = 0; i < array.length; i += 1)
					{
						if(!array[i])
						{
							dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, bytes) );
							continue;
						}
						
						var obj:Object = array[i];
						
						if( !obj.type || !obj.def || !obj.data || !(obj.type is uint) || !(obj.def is uint) || !(obj.data is String) )
						{
							dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, bytes) );
							continue;
						}
						
						var type:uint = obj.type;
						var def:uint = obj.def;
						var dataStr:String = obj.data;
						
						try{var dataBytes:ByteArray = Base64.decode(dataStr);}
						catch(e:Error)
						{
							dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, bytes) );
							continue;
						}
						
						var parsedData:Object = Packet.parseData(type, dataBytes);
						if(parsedData == null)
						{
							dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, bytes) );
							continue;
						}
						
						dispatchEvent( new DataEvent(DataEvent.DATA_RECEIVE, false, false, null, type, def, parsedData) );
					}
				}
			}
		}
		
		/** 패킷 뭉쳐 보내기 */
		private function _unitedSend(e:TimerEvent):void
		{
			if(_unitedBuffer.length > 0)
			{
				var i:uint;
				var len:uint = _unitedBuffer.length;
				var arr:Array = [];
				
				//Vector to Array
				for(i = 0; i < len; i += 1)
				{
					arr[i] = _unitedBuffer[i];
				}
				
				var str:String = JSON.stringify(arr);
				var bytes:ByteArray = new ByteArray();
				bytes.writeMultiByte(str, EncodingFormat.encoding);
				
				_sendSystemData(DataDefinition.UNITED_PACKET, bytes, false);
				
				_unitedBuffer.length = 0;
			}
		}
		
		/** 연결 상태를 검사 */
		private function _checkConnection(e:TimerEvent):void
		{
			// 일정 시간 이상 전송이 오지 않을 경우 접속이 끊긴 것으로 간주하여 이쪽에서도 접속을 끊는다.
			if(elapsedTimeAfterLastReceived > _idleTimeoutLimit)
			{
				_record.addRecord(true, "Connection to close(NoResponding)(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
				
				_close();
				
				dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
			}
		}
		
		/** 정보 수신 */
		private function _listen(e:ProgressEvent):void
		{
			var packetBytes:ByteArray; //바이트 배열 형태의 패킷.
			var cameBytes:ByteArray; //이번에 새로 들어온 데이터
			
			//읽을 데이터가 없을 경우
			if(_socket.bytesAvailable <= 0)
			{
				return;
			}
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함이다.
			_socket.endian = Endian.LITTLE_ENDIAN;
			
			cameBytes = new ByteArray();
			//_socket의 데이터를 cameBytes에 쓴다.
			_socket.readBytes(cameBytes);
			
			//마지막 통신 시간을 갱신한다.
			updateLastReceivedTime();
			dispatchEvent( new DataEvent(DataEvent.DATA_COME, false, false, null, 0, 0, cameBytes) );
			
			//백업해 놓은 바이트 배열을 가지고 온다.
			packetBytes = _getBackupBuffer();
			packetBytes.position = 0;
			packetBytes.writeBytes(cameBytes);
			
			var datas:Vector.<Object> = Packet.parse(packetBytes);
			
			var i:uint;
			var len:uint = datas.length;
			var data:Object;
			var inData:Object;
			for(i = 0; i < len; i += 1)
			{
				data = datas[i];
				inData = data.packet;
				
				if(data.event == ParsedNode.RECEIVE_EVENT)
				{
					dispatchEvent( new DataEvent(DataEvent.DATA_RECEIVE, false, false, null, inData.type, inData.def, inData.data) );
				}
				if(data.event == ParsedNode.INVALID_EVENT)
				{
					dispatchEvent( new DataEvent(DataEvent.INVALID_DATA, false, false, null, 0, 0, inData.data) );
				}
			}
			
			//남은 데이터를 나중에 다시 쓰기 위해 저장해 둔다.
			_backupData(packetBytes);
		}
		
		/** 백업해 놓은 바이트 배열을 반환한다. */
		private function _getBackupBuffer():ByteArray
		{
			return _backupBuffer;
		}
		
		/** 다 처리하고 난 후에도 남아 있는(패킷이 다 오지 않아 처리가 안 된) 데이터를 소켓의 _backupBytes에 임시로 저장해 둔다. */
		private function _backupData(bytes:ByteArray):void
		{
			if(bytes.length > 0)
			{
				_backupBuffer.clear();
				_backupBuffer.writeBytes(bytes, 0);
			}
		}
	} // class
} // package