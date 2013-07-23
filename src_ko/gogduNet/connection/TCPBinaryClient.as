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
	
	/** 연결이 성공한 경우 발생합니다. */
	[Event(name="connect", type="gogduNet.events.GogduNetEvent")]
	/** 서버 등에 의해 비자발적으로 연결이 끊긴 경우 발생<p/>
	 * (close() 함수로는 발생하지 않는다.) */
	[Event(name="close", type="gogduNet.events.GogduNetEvent")]
	/** 정상적인 데이터를 완전히 수신했을 때 발생. 데이터는 가공되어 이벤트로 전달된다.
	 * <p/>(dataType:DataType.BYTES, dataDefinition, data)
	 */
	[Event(name="receiveData", type="gogduNet.events.DataEvent")]
	/** 데이터를 전송 받는 중일 때 발생. 지금까지 전송 받은 데이터가 이벤트로 전달된다.<p/>
	 * (dataDefinition 속성이 존재하면 사용자가 보낸 (헤더와 프로토콜을 제외한)실질적인 데이터의 전송 상태를
	 * data 속성으로 전달하며, dataDefinition 속성이 존재하지 않으면(null)
	 * 아직 헤더나 프로토콜이 다 전송되지 않은 걸 의미하며, 헤더와 프로토콜이 포함된 바이트 배열이 전달된다)<p/>
	 * (데이터의 크기가 적어 너무 빨리 다 받은 경우엔 이 이벤트가 발생하지 않을 수도 있다.)
	 * <p/>(dataType:DataType.BYTES, dataDefinition:null or String, data:null or ByteArray)
	 */
	[Event(name="progressData", type="gogduNet.events.DataEvent")]
	/** 연결 시도가 실패한 경우 발생한다.<p/>
	 * IOErrorEvent.IO_ERROR : IO_ERROR로 연결 실패<p/>
	 * SecurityErrorEvent.SECURITY_ERROR : SECURITY_ERROR로 연결 실패<p/>
	 * "Timeout" : 연결 시간 초과<p/>
	 * "Saturation" : 서버측 최대 인원 초과
	 * <p/>( data:<p/>실패한 이유(IOErrorEvent.IO_ERROR or SecurityErrorEvent.SECURITY_ERROR or "Timeout" or "Saturation") )
	 */
	[Event(name="connectFail", type="gogduNet.events.GogduNetEvent")]
	/** 연결이 업데이트(정보를 수신)되면 발생 */
	[Event(name="connectionUpdate", type="gogduNet.events.GogduNetEvent")]
	
	/** 2진 파일 전송용 TCP 클라이언트입니다.<p/>
	 * 한 번에 최대 4기가의 데이터를 전송할 수 있으며, 수신 진행 상황을
	 * 이벤트로 알려주므로 파일 전송용으로 사용하기 좋습니다.<p/>
	 * 주의할 점으로 전송할 데이터의 크기(용량)이 큰 경우, TCP의 특성상 하나의 연결(하나의 TCPBinaryClient 객체)에선
	 * 한 번에 하나의 데이터만 전송하는 것이 좋습니다.<p/>
	 * (이전의 데이터가 모두 전송되기 전에 다른 데이터를 다시 전송하지 마세요)<p/>
	 * (네이티브 플래시의 소켓과 달리, close() 후에도 다시 사용할 수 있습니다.)
	 * 
	 * @langversion 3.0
	 * @playerversion Flash Player 11
	 * @playerversion AIR 3.0
	 */
	public class TCPBinaryClient extends ClientBase
	{
		/** 내부적으로 정보 수신이나 연결 검사 등을 위해 사용되는 타이머 */
		private var _timer:Timer;
		
		/** 최대 연결 지연 한계 */
		private var _connectionDelayLimit:Number;
		
		/** 서버와 마지막으로 통신한 시각(정확히는 마지막으로 서버로부터 정보를 전송 받은 시각) */
		private var _lastReceivedTime:Number;
		
		/** 소켓 */
		private var _socket:Socket;
		/** 서버 address */
		private var _serverAddress:String;
		/** 서버 포트 */
		private var _serverPort:int;
		/** 서버 인코딩 유형(기본값="UTF-8") */
		private var _encoding:String;
		
		// 상태
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
		 * <p>connectionDelayLimit : 연결 지연 한계(ms)<p/>
		 * (여기서 설정한 시간 동안 서버로부터 데이터가 오지 않으면 서버와 연결이 끊긴 것으로 간주한다.)</p>
		 * <p>encoding : 프로토콜 문자열의 변환에 사용할 인코딩 형식</p>
		 */
		public function TCPBinaryClient(serverAddress:String, serverPort:int, timerInterval:Number=100,
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
		
		/** 플래시의 네이티브 소켓을 가져온다. */
		public function get socket():Socket
		{
			return _socket;
		}
		
		/** 서버의 address를 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
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
		
		/** 서버의 포트를 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
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
		
		/** 프로토콜 바이트의 문자열 변환에 사용할 인코딩 유형을 가져오거나 설정한다. 설정은 연결하고 있지 않을 때에만 할 수 있다. */
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
		
		/** 서버와 연결을 시도한다. */
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
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, e.type) );
		}
		
		/** SecurityErrorEvent.SECURITY_ERROR로 연결이 실패 */
		private function _socketConnectFail2(e:SecurityErrorEvent):void
		{
			_socket.removeEventListener(Event.CONNECT, _socketConnect);
			_socket.removeEventListener(IOErrorEvent.IO_ERROR, _socketConnectFail);
			_socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _socketConnectFail2);
			
			_record.addRecord(true, "Failed connect to server(SecurityErrorEvent)");
			
			dispatchEvent( new GogduNetEvent(GogduNetEvent.CONNECT_FAIL, false, false, e.type) );
		}
		
		/** 서버와의 연결을 끊는다. */
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
		
		/** 2진 데이터를 전송한다. 함수 내부에서 자동으로 데이터에 헤더를 붙이지만, 이벤트로 데이터를 넘길 때 헤더가 자동으로 제거되므로
		 * 신경 쓸 필요는 없다. 그리고 definition(프로토콜 문자열)은 암호화되어 전송되고, 받았을 때 복호화되어 이벤트로 넘겨진다. 이
		 * 역시 클래스 내부에서 자동으로 처리되므로 신경 쓸 필요는 없다.(Encryptor 클래스를 수정하여 암호화 부분 수정 가능)
		 * 단, 데이터 부분은 자동으로 암호화되지 않으므로 직접 암호화 처리를 해야 한다.<p/>
		 * ( 한 번에 전송할 수 있는 data의 최대 길이는 uint로 표현할 수 있는 최대값인 4294967295(=4GB)이며,
		 * definition 문자열의 최대 길이도 uint로 표현할 수 있는 최대값인 4294967295이다. )<p/>
		 * (data 인자에 null을 넣으면, data는 길이가 0으로 전송된다.)
		 */
		public function sendBytes(definition:String, data:ByteArray=null):Boolean
		{
			if(_isConnected == false){return false;}
			
			//패킷 생성
			var packet:ByteArray = new ByteArray();
			//(프로토콜 문자열은 암호화되어 전송된다.)
			var defBytes:ByteArray = new ByteArray();
			defBytes.writeMultiByte( Encryptor.encode(definition), _encoding );
			
			//data가 존재할 경우
			if(data)
			{
				//헤더 생성
				packet.writeUnsignedInt( data.length ); //data size
				packet.writeUnsignedInt( defBytes.length ); //protocol length
				packet.writeBytes(defBytes, 0, defBytes.length); //protocol
				packet.writeBytes(data, 0, data.length); //data
			}
			
			//data가 null일 경우
			if(!data)
			{
				//헤더 생성
				packet.writeUnsignedInt( 0 ); //data size
				packet.writeUnsignedInt( defBytes.length ); //protocol length
				packet.writeBytes(defBytes, 0, defBytes.length); //protocol
			}
			
			_socket.writeBytes( packet, 0, packet.length );
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
			var bytes:ByteArray; // 패킷을 읽을 때 보조용으로 쓰는 바이트 배열.
			
			var size:uint; //헤더에서 뽑아낸 파일의 최종 크기
			var protocolLength:uint; //헤더에서 뽑아낸 프로토콜 문자열의 길이
			var protocol:String; //프로토콜 문자열
			var data:ByteArray; //최종 데이터
			
			if(_socket.connected == false)
			{
				return;
			}
			if(_socket.bytesAvailable <= 0)
			{
				return;
			}
			
			// 서버의 마지막 연결 시각을 갱신.
			updateLastReceivedTime();
			
			packetBytes = new ByteArray();
			bytes = _backupBytes;
			bytes.position = 0;
			packetBytes.position = 0;
			packetBytes.writeBytes(bytes, 0, bytes.length);
			
			//만약 AS가 아닌 C# 등과 통신할 경우 엔디안이 다르므로 오류가 날 수 있다. 그걸 방지하기 위함.
			_socket.endian = Endian.LITTLE_ENDIAN;
			_socket.readBytes(packetBytes, packetBytes.length, _socket.bytesAvailable);
			bytes.length = 0; //bytes == _backupBytes
			
			//헤더가 다 전송되지 않은 경우
			if(packetBytes.length < 8)
			{
				packetBytes.position = 0;
				dispatchEvent( new DataEvent(DataEvent.PROGRESS_DATA, false, false, 
					null, DataType.BYTES, null, packetBytes) );
			}
			//패킷 바이트의 길이가 8 이상일 경우(즉, 크기 헤더와 프로토콜 문자열 길이 헤더가 있는 경우), 반복
			while(packetBytes.length >= 8)
			{
				packetBytes.position = 0;
				
				try
				{
					//헤더(크기 헤더)를 읽는다.
					size = packetBytes.readUnsignedInt(); //Unsigned Int : 4 byte
					
					//헤더(프로토콜 문자열 길이 헤더)를 읽는다.
					protocolLength = packetBytes.readUnsignedInt();
				}
				catch(e:Error)
				{
					//오류가 난 정보를 바이트 배열에서 제거
					bytes = new ByteArray();
					bytes.length = 0;
					bytes.position = 0;
					bytes.writeBytes(packetBytes, 0, packetBytes.length);
					packetBytes.length = 0;
					packetBytes.position = 0;
					//(length 인자를 0으로 주면, offset부터 읽을 수 있는 전부를 선택한다.)
					packetBytes.writeBytes(bytes, 8, 0);
					
					_record.addErrorRecord(true, e, "It occurred from read to data's header");
					break;
				}
				
				//프로토콜 문자열 길이 이상 전송 된 경우
				//(bytesAvailable == length - position)
				if(packetBytes.bytesAvailable >= protocolLength)
				{
					try
					{
						//프로토콜 문자열을 담고 있는 바이트 배열을 문자열로 변환
						protocol = packetBytes.readMultiByte(protocolLength, _encoding);
						//변환된 문자열을 본래 프로토콜(전송되는 프로토콜은 암호화되어 있다)로 바꾸기 위해 복호화
						protocol = Encryptor.decode(protocol);
					}
					catch(e:Error)
					{
						//오류가 난 정보를 바이트 배열에서 제거
						bytes = new ByteArray();
						bytes.length = 0;
						bytes.position = 0;
						bytes.writeBytes(packetBytes, 0, protocolLength);
						packetBytes.length = 0;
						packetBytes.position = 0;
						//(length 인자를 0으로 주면, offset부터 읽을 수 있는 전부를 선택한다.)
						packetBytes.writeBytes(bytes, protocolLength, 0);
						
						_record.addErrorRecord(true, e, "It occurred from protocol bytes convert to string and decode protocol string");
						break;
					}
					
					//원래 사이즈만큼, 완전히 전송이 된 경우
					//(bytesAvailable == length - position)
					if(packetBytes.bytesAvailable >= size)
					{
						data = new ByteArray();
						data.writeBytes( packetBytes, packetBytes.position, size );
						data.position = 0;
						
						/*_record.addRecord(true, "Data received(elapsedTimeAfterConnected:" + elapsedTimeAfterConnected + ")");*/
						
						dispatchEvent( new DataEvent(DataEvent.RECEIVE_DATA, false, false, 
							null, DataType.BYTES, protocol, data) );
						
						//사용한 정보를 바이트 배열에서 제거한다.
						bytes = new ByteArray();
						bytes.writeBytes(packetBytes, 0, packetBytes.length);
						packetBytes.clear();
						//(length 인자를 0으로 주면, offset부터 읽을 수 있는 전부를 선택한다.)
						packetBytes.writeBytes(bytes, 8 + protocolLength + size, 0);
					}
						//데이터가 아직 다 전송이 안 된 경우
					else
					{
						data = new ByteArray();
						data.writeBytes( packetBytes, packetBytes.position, packetBytes.bytesAvailable );
						data.position = 0;
						
						dispatchEvent( new DataEvent(DataEvent.PROGRESS_DATA, false, false, 
							null, DataType.BYTES, protocol, data) );
					}
				}
					//프로토콜 정보가 다 전송되지 않은 경우
				else
				{
					packetBytes.position = 0;
					dispatchEvent( new DataEvent(DataEvent.PROGRESS_DATA, false, false, 
						null, DataType.BYTES, null, packetBytes) );
				}
			}
			
			_backup(_backupBytes, packetBytes);
		}
		
		/** 다 처리하고 난 후에도 남아 있는(패킷이 다 오지 않아 처리가 안 된) 데이터를 소켓의 _backupBytes에 임시로 저장해 둔다. */
		private function _backup(backupBytes:ByteArray, bytes:ByteArray):void
		{
			if(bytes.length > 0)
			{
				backupBytes.clear();
				backupBytes.writeBytes(bytes, 0, bytes.length);
			}
		}
	} // class
} // package