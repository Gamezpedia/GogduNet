package gogduNet.connection
{
	import flash.utils.ByteArray;
	
	import gogduNet.utils.Encryptor;
	import gogduNet.utils.cloneByteArray;
	import gogduNet.utils.spliceByteArray;
	
	public class Packet
	{
		public static const START_MARKER:uint = 0xAAAA;
		public static const START_MARKER_SIZE:uint = 2;
		
		public static const END_MARKER:uint = 0xFFFF;
		public static const END_MARKER_SIZE:uint = 2;
		
		public static const HEADER_SIZE:uint = 9;
		
		public static const TYPE_HEADER_POSITION:uint = 2;
		public static const TYPE_HEADER_SIZE:uint = 2;
		
		public static const DEFINITION_HEADER_POSITION:uint = 3;
		public static const DEFINITION_HEADER_SIZE:uint = 2;
		
		public static const DATA_SIZE_HEADER_POSITION:uint = 5;
		public static const	DATA_SIZE_HEADER_SIZE:uint = 4;
		
		public static const	DATA_POSITION:uint = 9;
		
		public static const	CHECKSUM_SIZE:uint = 2;
		
		/** Don't create instance of this class */
		public function Packet()
		{
			throw new Error("Don't create instance of this class");
		}
		
		static public function create(type:uint, definition:uint, data:ByteArray=null):ByteArray
		{
			var dataSize:uint;
			if(data != null)
			{
				//데이터 타입이 def인데 데이터가 있는 경우
				if(type == DataType.DEFINITION)
				{
					throw new Error("DataType.DEFINITION 타입인 패킷은 data 인자가 null이어야 합니다.");
				}
				
				data = Encryptor.encode(data);
				dataSize = data.length;
				
				//데이터 타입이 system도 bytes도 string도 아닌데 데이터 사이즈가 0인 경우
				if(type != DataType.SYSTEM && type != DataType.BYTES && type != DataType.STRING && dataSize == 0)
				{
					throw new Error("데이터 타입이 DataType.SYSTEM나 DataType.BYTES, DataType.STRING이 아닌 패킷은 data 인자의 길이가 0보다 커야 합니다.");
				}
			}
			else
			{
				//데이터가 system도 def도 bytes도 string도 아닌데 데이터가 없는 경우
				if(type != DataType.SYSTEM && type != DataType.DEFINITION && type != DataType.BYTES && type != DataType.STRING)
				{
					throw new Error("데이터 타입이 DataType.SYSTEM나 DataType.DEFINITION, DataType.BYTES, DataType.STRING이 아닌 패킷은 data 인자가 null일 수 없습니다.");
				}
				
				dataSize = 0;
			}
			
			var packet:ByteArray = new ByteArray();
			
			packet.writeShort(START_MARKER); //Start Marker
			
			packet.writeByte(type); //타입 헤더
			packet.writeShort(definition); //definition 헤더
			
			packet.writeUnsignedInt(dataSize); //data 크기 헤더
			if(data != null)
			{
				packet.writeBytes(data); //실질적인 데이터 영역
			}
			
			packet.writeShort( _getChecksum(packet) ); //체크섬 데이터
			
			packet.writeShort(END_MARKER); //End Marker
			
			return packet;
		}
		
		/** {event:"invalid" or "receive", packet:{type, def, data}}
		 * 데이터가 다 오지 않은 등의 이유로 처리하지 못한 패킷은 인자로 넣은 바이트에 그대로 있다. */
		static public function parse(bytes:ByteArray):Vector.<Object>
		{
			var vector:Vector.<Object> = new <Object>[];
			var startPosition:uint = 0; //패킷을 읽기 시작할 위치
			
			bytes.position = 0;
			
			//읽을 수 있는 바이트가 패킷 헤더의 크기보다 작은 경우
			if(bytes.bytesAvailable < HEADER_SIZE)
			{
				return vector;
			}
			
			//처음의 바이트가 시작 마커가 아닌 경우
			if(_checkStartMarker(bytes) == false)
			{
				var bool:Boolean = _nextOrRemove();
				if(bool == false){return vector;}
				else{bytes.position = 0;}
			}
			
			//읽을 수 있는 바이트가 최소한 패킷 헤더의 크기보다 큰 경우
			while(bytes.bytesAvailable >= HEADER_SIZE)
			{
				var type:uint = _getTypeHeader(bytes, startPosition);
				var def:uint = _getDefHeader(bytes, startPosition);
				var dataSize:uint = _getDataSizeHeader(bytes, startPosition);
				
				//데이터를 읽을 수 있는가?
				if(_isCanReadData(bytes, startPosition, dataSize) == false)
				{
					bool = _nextStartMarker();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				//체크섬 정보를 읽을 수 있는가?
				if(_isCanReadChecksum(bytes, startPosition, dataSize) == false)
				{
					bool = _nextStartMarker();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				var checksumData:uint = _getChecksumData(bytes, startPosition, dataSize);
				
				var onePacketBytes:ByteArray = cloneByteArray(bytes);
				//(spliceByteArray의 세 번째 인자에 0을 넣으면 두 번째 인자부터 모든 데이터를 제거하기 때문에)
				if(startPosition != 0)
				{
					//subtraction Previous data
					spliceByteArray(onePacketBytes, 0, startPosition);
				}
				//subtraction Checksum subtraction End Marker subtraction Next data
				spliceByteArray(onePacketBytes, HEADER_SIZE + dataSize);
				
				var checksum:uint = _getChecksum(onePacketBytes);
				
				//패킷의 체크섬 데이터와 계산한 체크섬이 일치하지 않는 경우
				if(checksumData != checksum)
				{
					bool = _nextStartMarker();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				if(_isCanReadEndMarker(bytes, startPosition, dataSize) == false)
				{
					bool = _nextStartMarker();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				//엔드 마커가 옳바르지 않을 경우
				if(_getEndMarker(bytes, startPosition, dataSize) != END_MARKER)
				{
					bool = _nextStartMarker();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				//타입이 def
				if(type == DataType.DEFINITION)
				{
					_pushReturnObject(vector, "receive", type, def, null);
					
					bool = _nextStartMarker();
					if(bool == true){continue;}
					else{return vector;}
				}
				//데이터의 크기가 0
				if(dataSize ==0)
				{
					//패킷의 타입이 system이나 bytes인 경우
					if(type == DataType.SYSTEM || type == DataType.BYTES)
					{
						_pushReturnObject(vector, "receive", type, def, new ByteArray());
						
						bool = _nextStartMarker();
						if(bool == true){continue;}
						else{return vector;}
					}
					//타입이 string인 경우
					else if(type == DataType.STRING)
					{
						_pushReturnObject(vector, "receive", type, def, "");
						
						bool = _nextStartMarker();
						if(bool == true){continue;}
						else{return vector;}
					}
					//타입이 system도 bytes도 string도 아닌 경우
					else
					{
						bool = _nextOrRemove();
						if(bool == true){continue;}
						else{return vector;}
					}
				}
				
				var dataBytes:ByteArray = _getData(bytes, startPosition, dataSize);
				var decodedData:ByteArray = Encryptor.decode(dataBytes);
				
				if(decodedData == null)
				{
					bool = _nextOrRemove();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				var dataObj:Object = _parseData(type, decodedData);
				
				if(dataObj == null)
				{
					bool = _nextOrRemove();
					if(bool == true){continue;}
					else{return vector;}
				}
				
				_pushReturnObject(vector, "receive", type, def, dataObj);
				
				bool = _nextStartMarker();
				if(bool == true){continue;}
				else{return vector;}
			}
			
			return vector;
			
			//true:you do 'continue;' or nothing, false:you do 'return vector;'
			function _nextOrRemove():Boolean
			{
				//반환 목록에 추가
				_pushReturnObject(vector, "invalid", 0, 0, bytes);
				
				/* 잘못된 데이터를 제거한다. */
				var index:Object = _indexOfStartMarker(bytes, startPosition + 1);
				
				if(index == null)
				{
					bytes.clear();
					return false;
				}
				else
				{
					var indexNum:uint = uint(index);
					spliceByteArray(bytes, 0, indexNum);
					return true;
				}
			}
			
			//true:you do 'continue;', false:you do 'return vector;'
			function _nextStartMarker():Boolean
			{
				var index:Object = _indexOfStartMarker(bytes, startPosition + 1);
				
				if(index == null)
				{
					return false;
				}
				
				var indexNum:uint = uint(index);
				startPosition = indexNum;
				return true;
			}
		}
		
		/** 반환 목록에 추가 */
		static private function _pushReturnObject(vector:Vector.<Object>, event:String, type:uint, def:uint, data:Object):void
		{
			vector.push( {event:event, packet:{type:type, def:def, data:data}} );
		}
		
		static private function _checkStartMarker(bytes:ByteArray):Boolean
		{
			var sm:uint = bytes.readUnsignedShort();
			
			if(sm == START_MARKER)
			{
				return true;
			}
			
			return false;
		}
		
		//return uint or null
		static private function _indexOfStartMarker(bytes:ByteArray, startIndex:uint=0):Object
		{
			var i:uint;
			var len:uint = bytes.length - START_MARKER_SIZE;
			
			for(i = startIndex; i <= len; i += 1) //Not '<'
			{
				bytes.position = i;
				if(bytes.readUnsignedShort() == START_MARKER)
				{
					return i;
				}
			}
			
			return null;
		}
		
		static private function _getTypeHeader(bytes:ByteArray, startPosition:uint):uint
		{
			bytes.position = startPosition + TYPE_HEADER_POSITION;
			
			return bytes.readUnsignedByte();
		}
		
		static private function _getDefHeader(bytes:ByteArray, startPosition:uint):uint
		{
			bytes.position = startPosition + DEFINITION_HEADER_POSITION;
			
			return bytes.readUnsignedShort();
		}
		
		static private function _getDataSizeHeader(bytes:ByteArray, startPosition:uint):uint
		{
			bytes.position = startPosition + DATA_SIZE_HEADER_POSITION;
			
			return bytes.readUnsignedInt();
		}
		
		static private function _isCanReadData(bytes:ByteArray, startPosition:uint, dataSize:uint):Boolean
		{
			bytes.position = startPosition + DATA_POSITION;
			
			if(bytes.bytesAvailable >= dataSize)
			{
				return true;
			}
			
			return false;
		}
		
		static private function _isCanReadChecksum(bytes:ByteArray, startPosition:uint, dataSize:uint):Boolean
		{
			bytes.position = startPosition + HEADER_SIZE + dataSize;
			
			if(bytes.bytesAvailable >= CHECKSUM_SIZE)
			{
				return true;
			}
			
			return false;
		}
		
		static private function _getChecksumData(bytes:ByteArray, startPosition:uint, dataSize:uint):uint
		{
			bytes.position = startPosition + HEADER_SIZE + dataSize;
			
			return bytes.readUnsignedShort();
		}
		
		static private function _getChecksum(bytes:ByteArray):uint
		{
			var i:uint;
			var len:uint = bytes.length;
			var sum:uint = 0;
			
			for(i = 0; i < len; i += 1)
			{
				sum += bytes[i];
			}
			
			return (sum & 0xff) + (sum >> 16);
		}
		
		static private function _isCanReadEndMarker(bytes:ByteArray, startPosition:uint, dataSize:uint):Boolean
		{
			bytes.position = startPosition + HEADER_SIZE + dataSize + CHECKSUM_SIZE;
			
			if(bytes.bytesAvailable >= END_MARKER_SIZE)
			{
				return true;
			}
			
			return false;
		}
		
		static private function _getEndMarker(bytes:ByteArray, startPosition:uint, dataSize:uint):uint
		{
			bytes.position = startPosition + DATA_POSITION + dataSize + CHECKSUM_SIZE;
			
			return bytes.readUnsignedShort();
		}
		
		static private function _getData(bytes:ByteArray, startPosition:uint, dataSize:uint, result:ByteArray=null):ByteArray
		{
			if(result == null)
			{
				result = new ByteArray();
			}
			
			bytes.position = startPosition + DATA_POSITION;
			bytes.readBytes(result);
			return result;
		}
		
		/** data 인자로부터 type 인자에 맞는 데이터를 추출한다. 잘못된 패킷인 경우엔 null을 반환한다. */
		static private function _parseData(type:int, bytes:ByteArray):Object
		{
			var obj:Object = null;
			var str:String;
			
			// type 문자열을 참고하여 알맞은 유형으로 byte를 변환한다.
			switch(type)
			{
				
				case DataType.SYSTEM:
				{
					bytes.position = 0;
					var result:ByteArray = new ByteArray();
					bytes.readBytes(result);
					
					return result;
				}
				break;
				
				case DataType.DEFINITION:
				{
					return null;
				}
				break;
				
				case DataType.BOOLEAN:
				{
					if(bytes.length >= 1)
					{
						bytes.position = 0;
						obj = bytes.readBoolean();
					}
				}
				break;
				
				case DataType.BYTE:
				{
					if(bytes.length >= 1)
					{
						bytes.position = 0;
						obj = bytes.readByte();
					}
				}
				break;
				
				case DataType.UNSIGNED_BYTE:
				{
					if(bytes.length >= 1)
					{
						bytes.position = 0;
						obj = bytes.readUnsignedByte();
					}
				}
				break;
				
				case DataType.SHORT:
				{
					if(bytes.length >= 2)
					{
						bytes.position = 0;
						obj = bytes.readShort();
					}
				}
				break;
				
				case DataType.UNSIGNED_SHORT:
				{
					if(bytes.length >= 2)
					{
						bytes.position = 0;
						obj = bytes.readUnsignedShort();
					}
				}
				break;
				
				case DataType.INT:
				{
					if(bytes.length >= 4)
					{
						bytes.position = 0;
						obj = bytes.readInt();
					}
				}
				break;
				
				case DataType.UNSIGNED_INT:
				{
					if(bytes.length >= 4)
					{
						bytes.position = 0;
						obj = bytes.readUnsignedInt();
					}
				}
				break;
				
				case DataType.FLOAT:
				{
					if(bytes.length >= 4)
					{
						bytes.position = 0;
						obj = bytes.readFloat();
					}
				}
				break;
				
				case DataType.DOUBLE:
				{
					if(bytes.length >= 8)
					{
						bytes.position = 0;
						obj = bytes.readDouble();
					}
				}
				break;
				
				case DataType.BYTES:
				{
					bytes.position = 0;
					result = new ByteArray();
					bytes.readBytes(result);
					
					return result;
				}
				break;
				
				case DataType.STRING:
				{
					try
					{
						bytes.position = 0;
						str = bytes.readMultiByte(bytes.length, EncodingFormat.encoding);
						
						return str;
					}
					catch(e:Error)
					{
						return null;
					}
				}
				break;
				
				case DataType.ARRAY:
				{
					try
					{
						bytes.position = 0;
						str = bytes.readMultiByte(bytes.length, EncodingFormat.encoding);
						var arr:Array = JSON.parse(str) as Array;
						
						return arr;
					}
					catch(e:Error)
					{
						return null;
					}
				}
				break;
				
				case DataType.OBJECT:
				{
					try
					{
						bytes.position = 0;
						str = bytes.readMultiByte(bytes.length, EncodingFormat.encoding);
						obj = JSON.parse(str);
						
						return obj;
					}
					catch(e:Error)
					{
						return null;
					}
				}
				break;
			}
			
			//필요한 데이터를 읽는 데 성공한 경우
			if(obj != null)
			{
				//필요한 데이터를 읽은 후에도 읽을 바이트가 더 남아 있는 경우
				if(bytes.bytesAvailable > 0)
				{
					//잘못된 패킷이라고 판단하고 null을 반환한다.
					return null;
				}
				else
				{
					return obj;
				}
			}
			
			return null;
		}
	}
}