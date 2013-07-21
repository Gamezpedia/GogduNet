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
	
	/** 연결이 성공한 경우 발생 */
	[Event(name="connect", type="gogduNet.events.GogduNetEvent")]
	/** 서버 등에 의해 비자발적으로 연결이 끊긴 경우 발생(close() 함수로는 발생하지 않는다.) */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 정상적인 데이터를 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.
	 * </br>(dataType, dataDefinition, data)
	 */
	[Event(name="receiveData", type="gogduNet.events.DataEvent")]
	/** 정상적이지 않은 데이터를 수신했을 때 발생
	 * </br>(dataType:DataType.INVALID, dataDefinition:"Wrong" or "Surplus", data:잘못된 패킷의 ByteArray)
	 */
	[Event(name="invalidPacket", type="gogduNet.events.DataEvent")]
	/** 연결 시도가 실패한 경우 발생한다. 주의할 점으로, 서버의 인원 초과로 인해 연결이 실패한 경우엔 이 이벤트가 발생하지 않는다.
	 * 인원 초과 검사를 잠깐이나마 연결이 되었기 때문이다. 서버 인원 초과로 인해 연결이 실패한 경우엔 GogduNetEvent.CONNECT 이벤트가 발생하고
	 * 잠깐의 시간 뒤에 서버에 의해 GogduNetEvent.CLOSE 이벤트가 발생한다.
	 * ( 단지 실패했음을 알리는 Definition 데이터를 전송 받을 뿐이다.(dataDefinition:Connect.Fail.Saturation) )</br>
	 * 따라서 서버 인원 초과로 연결이 실패한 경우를 알아내려면 DataEvent.RECEIVE_DATA 이벤트를 이용하여
	 * Connect.Fail.Saturation란 Definition 타입 데이터가 수신되는지를 검사해야 한다.
	 * </br>( data:실패한 이유(IOErrorEvent.IO_ERROR or SecurityErrorEvent.SECURITY_ERROR) )
	 */
	[Event(name="connectFail", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	
	/** JSON 문자열을 기반으로 하여 통신하는 TCP 클라이언트
	 * (네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)
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
		
		/** <p>serverAddress : 연결할 서버의 address</p>
		 * <p>serverPort : 연결할 서버의 포트</p>
		 * <p>timerInterval : 정보 수신과 연결 검사를 할 때 사용할 타이머의 반복 간격(ms)</p>
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)(여기서 설정한 시간 동안 서버로부터 데이터가 오지 않으면 서버와 연결이 끊긴 것으로 간주한다.)</p>
		 * <p>encoding : 통신을 할 때 사용할 인코딩 형식</p>
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
		
		/** 내부적으로 정보 수신이나 연결 검사 등을 위해 사용되는 타이머의 재생 간격을 가져오거나 설정한다.(ms) */
		public function get timerInterval():Number
		{
			return _timer.delay;
		}
		public function set timerInterval(value:Number):void
		{
			_timer.delay = value;
		}
		
		/** 연결 지연 한계 시간을 가져오거나 설정한다.(ms)
		 * 이 시간을 넘도록 정보가 수신되지 않은 경우엔 연결이 끊긴 것으로 간주하고 이쪽에서도 연결을 끊는다.
		 */
		public function get connectionDelayLimit():Number
		{
			return _connectionDelayLimit;
		}
		public function set connectionDelayLimit(value:Number):void
		{
			_connectionDelayLimit = value;
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
		
		/** 통신 인코딩 유형을 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
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
			
			_connectedTime = getTimer();
			updateLastReceivedTime();
			_record.addRecord(true, "Connected to server(connectedTime:" + _connectedTime + ")");
			
			_socket.addEventListener(Event.CLOSE, _socketClosed);
			
			_timer.start();
			_timer.addEventListener(TimerEvent.TIMER, _timerFunc);
			
			_isConnected = true;
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT) );
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
		
		/** 서버와의 연결을 끊음 */
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