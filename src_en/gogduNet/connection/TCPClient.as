package gogduNet.connection
{
	import flash.events.Event;
	import flash.events.IOErrorEvent;
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
	import gogduNet.utils.DataType;
	import gogduNet.utils.Encryptor;
	import gogduNet.utils.RecordConsole;
	import gogduNet.utils.makePacket;
	import gogduNet.utils.parsePacket;
	
	/** This occurs when connection succeed. */
	[Event(name="connect", type="gogduNet.events.GogduNetEvent")]
	/** This occurs when involuntary closed connection because of server, etc.<p/>
	 * (Does not occurs when close() function)
	 */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** This occurs when received whole packet and Packet is dispatch to event after processed
	 * <p/>(dataType, dataDefinition, data)
	 */
	[Event(name="receiveData", type="gogduNet.events.DataEvent")]
	/** This occurs when received abnormal packet
	 * <p/>(dataType:DataType.INVALID, dataDefinition:"Wrong" or "Surplus", data:ByteArray of abnormal packet)
	 */
	[Event(name="invalidPacket", type="gogduNet.events.DataEvent")]
	/** This occurs when failed to connecting.<p/>
	 * IOErrorEvent.IO_ERROR : Failed to connecting because IO_ERROR<p/>
	 * SecurityErrorEvent.SECURITY_ERROR : Failed to connecting because SECURITY_ERROR<p/>
	 * "Timeout" : Connection timeout<p/>
	 * "Saturation" : Exceeded maximum connection number of server
	 * <p/>( data:<p/>Why failed(IOErrorEvent.IO_ERROR or SecurityErrorEvent.SECURITY_ERROR or "Timeout" or "Saturation") )
	 */
	[Event(name="connectFail", type="gogduNet.events.GogduNetEvent")]
	/** This occurs when update connection. (When received data) */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	
	/** TCP client which communicate by base on JSON string<p/>
	 * (Unlike Socket of native flash, this is usable after close() function)
	 * 
	 * @langversion 3.0
	 * @playerversion Flash Player 11
	 * @playerversion AIR 3.0
	 */
	public class TCPClient extends ClientBase
	{
		/** 내부적으로 정보 수신이나 연결 검사 등을 위해 사용되는 타이머 */
		private var _timer:Timer;
		
		/** 최대 연결 지연 한계 */
		private var _connectionDelayLimit:Number;
		
		/** 서버와 마지막으로 통신한 시각(정확히는 마지막으로 서버로부터 정보를 전송 받은 시각) */
		private var _lastReceivedTime:Number;
		
		/** 네이티브 소켓 */
		private var _socket:Socket;
		/** 연결할 서버의 address */
		private var _serverAddress:String;
		/** 연결할 서버의 포트 */
		private var _serverPort:int;
		/** 통신 인코딩 유형(기본값="UTF-8") */
		private var _encoding:String;
		
		/** 현재 연결되어 있는가를 나타내는 bool 값 */
		private var _isConnected:Boolean;
		/** 연결된 지점의 시간을 나타내는 변수 */
		private var _connectedTime:Number;
		/** 디버그용 기록 */
		private var _record:RecordConsole;
		
		/** 수신되었으나 아직 처리되지 않은 데이터들을 임시로 저장해 두는 바이트 배열 */
		private var _backupBytes:ByteArray;
		
		/** GogduNetEvent.CONNECTION_UPDATE 이벤트 객체 */
		private var _event:GogduNetEvent;
		
		/** <p>serverAddress : Address of server to connect</p>
		 * <p>serverPort : Port of server to connect</p>
		 * <p>timerInterval : Delay of Timer for to check connection and receive data.(ms)</p>
		 * <p>connectionDelayLimit : Connection delay limit(ms)<p/>
		 * (If data does not come from server for the time set here, consider disconnected with server.)</p>
		 * <p>encoding : Encoding format for communication</p>
		 */
		public function TCPClient(serverAddress:String, serverPort:int, timerInterval:Number=100,
								  connectionDelayLimit:Number=10000, encoding:String="UTF-8")
		{
			_timer = new Timer(timerInterval);
			_connectionDelayLimit = connectionDelayLimit;
			_lastReceivedTime = -1;
			_socket = new Socket();
			_serverAddress = serverAddress;
			_serverPort = serverPort;
			_encoding = encoding;
			_isConnected = false;
			_connectedTime = -1;
			_record = new RecordConsole();
			_backupBytes = new ByteArray();
			_event = new GogduNetEvent(GogduNetEvent.CONNECTION_UPDATE, false, false, null);
		}
		
		/** Get or set delay of Timer for to check connection and receive data.(ms) */
		public function get timerInterval():Number
		{
			return _timer.delay;
		}
		public function set timerInterval(value:Number):void
		{
			_timer.delay = value;
		}
		
		/** Get or set connection delay limit.(ms)<p/>
		 * (If data does not come from server for the time set here, consider disconnected with server.)
		 */
		public function get connectionDelayLimit():Number
		{
			return _connectionDelayLimit;
		}
		public function set connectionDelayLimit(value:Number):void
		{
			_connectionDelayLimit = value;
		}
		
		/** Get native socket of flash */
		public function get socket():Socket
		{
			return _socket;
		}
		
		/** Get or set address of server. Can be set only if not connected. */
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
		
		/** Get or set port of server. Can be set only if not connected. */
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
		
		/** Get or set encoding format for communication. Can be set only if not connected. */
		public function get encoding():String
		{
			return _encoding;
		}
		public function set encoding(value:String):void
		{
			if(_isConnected == true)
			{
				return;
			}
			
			_encoding = value;
		}
		
		/** Get whether currently connected */
		public function get isConnected():Boolean
		{
			return _isConnected;
		}
		
		/** Get RecordConsole Object which has record for debug */
		public function get record():RecordConsole
		{
			return _record;
		}
		
		/** Get elapsed time after connected.(ms) */
		public function get elapsedTimeAfterConnected():Number
		{
			if(_isConnected == false)
			{
				return -1;
			}
			
			return getTimer() - _connectedTime;
		}
		
		/** Get elapsed time after last received.(ms) */
		public function get elapsedTimeAfterLastReceived():Number
		{
			return getTimer() - _lastReceivedTime;
		}
		
		/** Update last received time.
		 * (Automatically updates by execute this function when received data from server)
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
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			_timer = null;
			
			_socket = null;
			_serverAddress = null;
			_encoding = null;
			_record.dispose();
			_record = null;
			_backupBytes = null;
			_event = null;
			
			_isConnected = false;
		}
		
		/** Tries to connect with server. */
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
			
			updateLastReceivedTime();
			
			_record.addRecord(true, "(Before validate)Connected to server");
			
			_timer.start();
			_timer.addEventListener(TimerEvent.TIMER, _timerFunc);
			
			this.addEventListener(DataEvent.RECEIVE_DATA, _receiveConnectPacket);
			
			setTimeout(_failReceiveConnectPacket, 5000);
		}
		
		private function _receiveConnectPacket(e:DataEvent):void
		{
			if(e.dataType == DataType.DEFINITION)
			{
				if(e.dataDefinition == "Connect.Success")
				{
					this.removeEventListener(DataEvent.RECEIVE_DATA, _receiveConnectPacket);
					
					_connectedTime = getTimer();
					
					_record.addRecord(true, "(After validate)Connected to server(connectedTime:" + _connectedTime + ")");
					
					_socket.addEventListener(Event.CLOSE, _socketClosed);
					_isConnected = true;
					
					dispatchEvent(new GogduNetEvent(GogduNetEvent.CONNECT));
				}
				else if(e.dataDefinition == "Connect.Fail.Saturation")
				{
					this.removeEventListener(DataEvent.RECEIVE_DATA, _receiveConnectPacket);
					
					_timer.stop();
					_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
					this.removeEventListener(DataEvent.RECEIVE_DATA, _receiveConnectPacket);
					
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
					_timer.stop();
					_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
					this.removeEventListener(DataEvent.RECEIVE_DATA, _receiveConnectPacket);
					
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
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			
			_record.addRecord(true, "Failed connect to server(IOErrorEvent)");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, null) );
		}
		
		/** SecurityErrorEvent.SECURITY_ERROR로 연결이 실패 */
		private function _socketConnectFail2(e:SecurityErrorEvent):void
		{
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			
			_record.addRecord(true, "Failed connect to server(SecurityErrorEvent)");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, null) );
		}
		
		/** Close connection with server. */
		public function close():void
		{
			if(_isConnected == false)
			{
				return;
			}
			
			_socket.close();
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			_socket.removeEventListener(Event.CLOSE, _socketClosed);
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			
			_record.addRecord(true, "Connection to close(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
			_isConnected = false;
		}
		
		/** Definition를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendDefinition(definition:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.DEFINITION, definition);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** String를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendString(definition:String, data:String):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.STRING, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** Array를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendArray(definition:String, data:Array):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.ARRAY, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** Integer를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendInteger(definition:String, data:int):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.INTEGER, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** Unsigned Integer를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendUnsignedInteger(definition:String, data:uint):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.UNSIGNED_INTEGER, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** Rationals를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendRationals(definition:String, data:Number):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.RATIONALS, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** Boolean를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 */
		public function sendBoolean(definition:String, data:Boolean):Boolean
		{
			if(_isConnected == false){return false;}
			
			var str:String = makePacket(DataType.BOOLEAN, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		/** JSON를 서버로 전송한다.
		 * 패킷 형식이 맞지 않거나 연결되어 있지 않다는 등의 이유로 전송이 실패한 경우 true를, 그 외엔 false를 반환한다.
		 * (data 인자엔 Object 타입 객체나, JSON 형식에 맞는 String 객체가 올 수 있다.)
		 */
		public function sendJSON(definition:String, data:Object):Boolean
		{
			if(_isConnected == false){return false;}
			
			if(data is String)
			{
				try
				{
					data = JSON.parse(String(data));
				}
				catch(e:Error)
				{
					return false;
				}
			}
			
			var str:String = makePacket(DataType.JSON, definition, data);
			if(str == null){return false;}
			
			_socket.writeMultiByte(str, _encoding);
			_socket.flush();
			return true;
		}
		
		private function _socketClosed(e:Event):void
		{
			_record.addRecord(true, "Connection to server is disconnected(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
			_isConnected = false;
			
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			_socket.removeEventListener(Event.CLOSE, _socketClosed);
			
			_timer.stop();
			_timer.removeEventListener(TimerEvent.TIMER, _timerFunc);
			
			dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
		}
		
		/** 타이머로 반복되는 함수 */
		private function _timerFunc(e:TimerEvent):void
		{
			_checkConnect();
			_listen();
		}
		
		/** 연결 상태를 검사 */
		private function _checkConnect():void
		{
			// 일정 시간 이상 전송이 오지 않을 경우 접속이 끊긴 것으로 간주하여 이쪽에서도 접속을 끊는다.
			if(elapsedTimeAfterLastReceived > _connectionDelayLimit)
			{
				_record.addRecord(true, "Connection to close(NoResponding)(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");
				close();
				dispatchEvent(new GogduNetEvent(GogduNetEvent.CLOSE));
			}
		}
		
		/** 정보 수신 */
		private function _listen():void
		{
			var packetBytes:ByteArray; // 패킷을 읽을 때 쓰는 바이트 배열.
			var bytes:ByteArray; // 패킷을 읽을 때 보조용으로 한 번만 쓰는 일회용 바이트 배열.
			var regArray:Array; // 정규 표현식으로 찾은 문자열들을 저장해 두는 배열
			var jsonObj:Object // JSON Object로 전환된 패킷을 담는 객체
			var packetStr:String; // byte을 String으로 변환하여 읽을 때 쓰는 문자열.
			var i:int;
			
			if(_socket.connected == false)
			{
				return;
			}
			if(_socket.bytesAvailable <= 0)
			{
				return;
			}
			
			// 마지막 연결 시각을 갱신.
			updateLastReceivedTime();
			
			// packetBytes는 socket.packetBytes + socketInSocket의 값을 가지게 된다.
			packetBytes = new ByteArray();
			bytes = _backupBytes;
			bytes.position = 0;
			packetBytes.position = 0;
			packetBytes.writeBytes(bytes, 0, bytes.length);
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함.
			_socket.endian = Endian.LITTLE_ENDIAN;
			_socket.readBytes(packetBytes, packetBytes.length, _socket.bytesAvailable);
			bytes.length = 0; //bytes == _backupBytes
			
			// 정보(byte)를 String으로 읽는다.
			try
			{
				packetBytes.position = 0;
				packetStr = packetBytes.readMultiByte(packetBytes.length, _encoding);
			}
			catch(e:Error)
			{
				_record.addErrorRecord(true, e, "It occurred from packet bytes convert to string");
				return;
			}
			
			// 필요 없는 잉여 패킷(잘못 전달되었거나 악성 패킷)이 있으면 제거한다.
			if(FILTER_REG_EXP.test(packetStr) == true)
			{
				_record.addRecord(true, "Sensed surplus packet(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(str:" + packetStr + ")");
				_record.addByteRecord(true, packetBytes);
				dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, null, DataType.INVALID, "Surplus", packetBytes));
				packetStr.replace(FILTER_REG_EXP, "");
			}
			
			//_reg:정규표현식 에 매치되는 패킷을 가져온다.
			regArray = packetStr.match(EXTRACTION_REG_EXP);
			//가져온 패킷을 문자열에서 제거한다.
			packetStr = packetStr.replace(EXTRACTION_REG_EXP, "");
			
			for(i = 0; i < regArray.length; i += 1)
			{
				if(!regArray[i])
				{
					continue;
				}
				
				// 패킷에 오류가 있는지를 검사합니다.
				jsonObj = parsePacket(regArray[i]);
				
				// 패킷에 오류가 있으면
				if(jsonObj == null)
				{
					_record.addRecord(true, "Sensed wrong packets(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")(str:" + regArray[i] + ")");
					_record.addByteRecord(true, packetBytes);
					dispatchEvent(new DataEvent(DataEvent.INVALID_PACKET, false, false, null, DataType.INVALID, "Wrong", packetBytes));
					continue;
				}
					// 패킷에 오류가 없으면
				else
				{
					if(jsonObj.t == DataType.DEFINITION)
					{
						/*_record.addRecord(true, "Data received(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");*/
						dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, null, jsonObj.t, jsonObj.df, null));
					}
					else
					{
						/*_record.addRecord(true, "Data received(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");*/
						dispatchEvent(new DataEvent(DataEvent.RECEIVE_DATA, false, false, null, jsonObj.t, jsonObj.df, jsonObj.dt));
					}
				}
			}
			
			// 다 처리하고 난 후에도 남아 있는(패킷이 다 오지 않아 처리가 안 된) 정보(byte)를 backupBytes에 임시로 저장해 둔다.
			if(packetStr.length > 0)
			{
				_backupBytes.length = 0;
				_backupBytes.position = 0;
				_backupBytes.writeMultiByte(packetStr, _encoding);
			}
		}
	} // class
} // package