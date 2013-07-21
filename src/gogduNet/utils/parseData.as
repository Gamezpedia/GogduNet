package gogduNet.utils
{
	/** data 인수로부터 type에 맞는 데이터를 추출한다. 실패한 경우엔 null을 반환한다. */
	public function parseData(type:String, data:Object):Object
	{
		// type 문자열을 참고하여 알맞은 유형으로 byte를 변환한다.
		switch(type)
		{
			// define
			case DataType.DEFINITION:
			{
				return null;
			}
			// string
			case DataType.STRING:
			{
				if( !(data is String) )
				{
					return null;
				}
				return data;
			}
			// array
			case DataType.ARRAY:
			{
				if( !(data is Array) )
				{
					return null;
				}
				return data;
			}
			// integer
			case DataType.INTEGER:
			{
				if( !(data is int) && !(data is uint) && !(data is Number) )
				{
					return null;
				}
				return int(data);
			}
			// unsigned integer
			case DataType.UNSIGNED_INTEGER:
			{
				if( !(data is int) && !(data is uint) && !(data is Number) )
				{
					return null;
				}
				return uint(data);
			}
			// rationals(rational number)
			case DataType.RATIONALS:
			{
				if( !(data is int) && !(data is uint) && !(data is Number) )
				{
					return null;
				}
				return Number(data);
			}
			// boolean(true or false)
			case DataType.BOOLEAN:
			{
				if( !(data is Boolean) )
				{
					return null;
				}
				return data;
			}
			// JSON
			case DataType.JSON:
			{
				if( !(data is Object) )
				{
					return null;
				}
				return data;
			}
			default:
			{
				return null;
			}
		}
		
		return null;
	}
}