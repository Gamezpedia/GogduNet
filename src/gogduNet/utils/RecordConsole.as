package gogduNet.utils
{
	import flash.filesystem.File;
	import flash.utils.ByteArray;
	import flash.utils.getTimer;
	
	/** 디버그용 문자열 기록을 관리하는 클래스입니다.
	 * Flash Player에서 사용하려면, saveRecord() 함수 부분을 수정하거나 주석 처리하세요.
	 */
	public class RecordConsole
	{
		public static const MAX_LENGTH:int = 10000000000;
		
		private var _record:String;
		private var _garbageRecords:Vector.<String>;
		private var _byteRecords:Vector.<ByteArray>;
		
		public function RecordConsole()
		{
			_record = '';
			addRecord(true, 'Start recording.');
			_garbageRecords = new Vector.<String>();
			_byteRecords = new Vector.<ByteArray>();
		}
		
		public function dispose():void
		{
			_record = null;
			_garbageRecords = null;
			_byteRecords = null;
		}
		
		public function addRecord(appendDate:Boolean, ...strings):String
		{
			if(_record.length > MAX_LENGTH)
			{
				_garbageRecords.push(_record);
				_record = "-Automatically cleared record. previous record is in 'garbageRecords'.\n";
			}
			
			var str:String = "";
			var i:uint;
			
			for(i = 0; i < strings.length; i += 1)
			{
				str += String(strings) + " ";
			}
			
			if(appendDate == true)
			{
				var date:Date = new Date();
				str =(date.fullYear + '/' + (date.month+1) + '/' + date.date + '/' + date.hours + ':' + date.minutes + ':' + date.seconds) + "(runningTime:" + getTimer() + ") " + str;
			}
			else
			{
				str = str;
			}
			
			_record += '-' + str + '\n';
			return str;
		}
		
		public function addByteRecord(appendDate:Boolean, bytes:ByteArray):uint
		{
			var i:uint = _byteRecords.push(bytes) - 1;
			addRecord(appendDate, "Bytes are added. it is in 'byteRecords' (index:" + String(i) + ")");
			return i;
		}
		
		public function addErrorRecord(appendDate:Boolean, error:Error, descript:String=""):String
		{
			var str:String = addRecord(appendDate, "Error(id:" + String(error.errorID) + ", name:" + error.name + ", message:" + error.message +
				")(toStr:" + error.toString() + ")(descript:" + descript + ")");
			return str;
		}
		
		public function clearRecord():void{
			_record ='';
			addRecord(true, 'Records are cleared');
		}
		
		public function clearGarbageRecords():void{
			addRecord(true, 'GarbageRecords are cleared');
			_garbageRecords.length =0;
		}
		
		public function clearByteRecords():void{
			addRecord(true, 'ByteRecords are clearred');
			_byteRecords.length =0;
		}
		
		public function get record():String
		{
			return _record;
		}
		
		public function get garbageRecords():Vector.<String>
		{
			return _garbageRecords;
		}
		
		public function get byteRecords():Vector.<ByteArray>
		{
			return _byteRecords;
		}
		
		/** for AIR
		 * @playerversion AIR 3.0
		 */
		public function saveRecord(url:String, addGarbageRecord:Boolean=true, addByteRecord:Boolean=true):void
		{
			var str:String = "[Records]";
			var i:uint;
			
			if(addGarbageRecord == true)
			{
				for(i = 0; i < _garbageRecords.length; i += 1)
				{
					str += _garbageRecords[i];
				}
			}
			
			str += _record;
			
			if(addByteRecord == true)
			{
				str += "\n\n[ByteRecords(Base64)]";
				
				for(i = 0; i < _byteRecords.length; i += 1)
				{
					str += "[" + i + "] " + Base64.encode(_byteRecords[i]);
				}
			}
			
			var file:File = new File(url);
			file.save(str);
		}
		
		public function toString():String
		{
			return _record;
		}
	}
}