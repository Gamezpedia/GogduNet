package gogduNet.utils
{
	public class ObjectPool
	{
		private var _objectClass:Class;
		private var _activeObjects:Array;
		private var _inactiveObjects:Array;
		
		/** 객체 재사용을 위한 오브젝트 풀. */
		public function ObjectPool(objectClass:Class)
		{
			_objectClass = objectClass;
			_activeObjects = new Array();
			_inactiveObjects = new Array();
		}
		
		/** 사용 중인 객체의 수를 가져온다. */
		public function get activeCount():uint
		{
			return _activeObjects.length;
		}
		
		/** 사용할 수 있는 객체의 수를 가져온다. */
		public function get inactiveCount():uint
		{
			return _inactiveObjects.length;
		}
		
		/** 객체를 하나 가져온다. inactiveCount가 0일 경우엔 새 객체를 만들어서 반환한다. */
		public function getInstance():Object
		{
			var instance:Object;
			
			if(_inactiveObjects.length == 0)
			{
				instance = new _objectClass();
			}
			else
			{
				instance = _inactiveObjects.pop();
			}
			
			_activeObjects.push(instance);
			return instance;
		}
		
		/** 사용이 끝난 객체를 오브젝트 풀에 반환한다.
		 * 주의할 점으로, 자동으로 dispose되지 않는다. 따라서 이 함수로 반환하기 전에
		 * 개발자가 직접 dispose해 주어야 한다. */
		public function returnInstance(object:Object):void
		{
			var i:int;
			
			for(i = 0; i < _activeObjects.length; i += 1)
			{
				if(_activeObjects[i] == object)
				{
					_activeObjects.splice(i, 1);
					_inactiveObjects.push(object);
				}
			}
		}
		
		public function clear():void
		{
			_activeObjects.length = 0;
			_inactiveObjects.length = 0;
		}
		
		public function dispose():void
		{
			_activeObjects = null;
			_inactiveObjects = null;
			_objectClass = null;
		}
	}
}