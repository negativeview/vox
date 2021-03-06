/// Copyright: Copyright (c) 2017-2019 Andrey Penechko.
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
/// Authors: Andrey Penechko.
module utils.array;

// Optimal for 1, 2, 4 byte items.
// Best with POT sized items
// Can store inline up to 8 bytes
struct Array(T)
{
	import utils : isPowerOfTwo, nextPOT, divCeil, min, max, writefln, ArrayArena, format;

	// Can be 0
	enum uint NUM_INLINE_ITEMS = size_t.sizeof / T.sizeof;
	enum uint MIN_EXTERNAL_BYTES = max(ArrayArena.MIN_BLOCK_BYTES, nextPOT((NUM_INLINE_ITEMS + 1) * T.sizeof));
	enum uint MIN_EXTERNAL_ITEMS = MIN_EXTERNAL_BYTES / T.sizeof;
	enum uint ARRAY_PAGE_BYTES = ArrayArena.MAX_BLOCK_BYTES;
	enum uint NUM_ITEMS_PER_PAGE = ARRAY_PAGE_BYTES / T.sizeof;

	private uint _length;
	private uint _capacity = NUM_INLINE_ITEMS;

	union
	{
		// Used when length <= NUM_INLINE_ITEMS
		private T[NUM_INLINE_ITEMS] inlineItems;

		// Used when length <= ARRAY_PAGE_BYTES / T.sizeof
		private T* externalArray;

		// Used when length > ARRAY_PAGE_BYTES / T.sizeof
		// Points to T*[ARRAY_PAGE_BYTES / ptr.sizeof]
		private T** chunkedArray;
	}

	bool empty() { return _length == 0; }
	uint length() { return _length; }
	uint opDollar() { return _length; }
	uint capacity() { return _capacity; }
	ref T front() { return this[0]; }
	ref T back() { return this[$-1]; }
	void clear() { _length = 0; }

	ref T opIndex(size_t index)
	{
		assert(index < _capacity, format("opIndex(%s), capacity %s", index, _capacity));
		static if (NUM_INLINE_ITEMS > 0)
			if (_capacity == NUM_INLINE_ITEMS)
				return inlineItems[index];

		if (capacity <= NUM_ITEMS_PER_PAGE)
			return externalArray[index];

		size_t chunkIndex = index / NUM_ITEMS_PER_PAGE;
		size_t chunkPos = index % NUM_ITEMS_PER_PAGE;
		return chunkedArray[chunkIndex][chunkPos];
	}

	Array!T dup(ref ArrayArena arena)
	{
		Array!T copy = this;

		static if (NUM_INLINE_ITEMS > 0)
			if (_capacity == NUM_INLINE_ITEMS)
				return copy;

		if (capacity <= NUM_ITEMS_PER_PAGE)
		{
			size_t byteCapacity = nextPOT(_capacity * T.sizeof);

			// When we have empty array with NUM_INLINE_ITEMS == 0 and no allocated external array
			if (byteCapacity == 0) return copy;

			ubyte[] block = (cast(ubyte*)externalArray)[0..byteCapacity];

			ubyte[] newBlock = arena.allocBlock(block.length);
			newBlock[] = block;
			copy.externalArray = cast(T*)newBlock.ptr;
			return copy;
		}

		size_t numPages = _capacity / NUM_ITEMS_PER_PAGE;
		size_t pageArrayCapacity = nextPOT(numPages);
		ubyte[] pageArray = cast(ubyte[])(chunkedArray[0..pageArrayCapacity]);
		ubyte[] newPageArrayBlock = arena.allocBlock(pageArray.length);
		copy.chunkedArray = cast(T**)newPageArrayBlock.ptr;
		foreach(i; 0..numPages) {
			ubyte[] page = arena.allocBlock(ARRAY_PAGE_BYTES);
			copy.chunkedArray[i] = cast(T*)page.ptr;
		}
		return copy;
	}

	void voidPut(ref ArrayArena arena, uint howMany)
	{
		if (_length + howMany > _capacity) extend(arena, howMany);
		_length += howMany;
	}

	void put(ref ArrayArena arena, T item)
	{
		if (_length == _capacity) extend(arena, 1);

		this[_length] = item;
		++_length;
	}

	void putFront(ref ArrayArena arena, T item)
	{
		putAt(arena, 0, item);
	}

	// shifts items to the right
	void putAt(ref ArrayArena arena, size_t at, T[] items...)
	{
		replaceAt(arena, at, 0, items);
	}

	void replaceAt(A)(ref ArrayArena arena, size_t at, size_t numItemsToRemove, A itemsToInsert)
	{
		assert(at + numItemsToRemove <= _length);

		size_t numItemsToInsert = itemsToInsert.length;

		replaceAtVoid(arena, at, numItemsToRemove, numItemsToInsert);
		foreach(i; 0..numItemsToInsert)
			this[at+i] = itemsToInsert[i];
	}

	void replaceAtVoid(ref ArrayArena arena, size_t at, size_t numItemsToRemove, size_t numItemsToInsert)
	{
		assert(at + numItemsToRemove <= _length);

		if (numItemsToInsert == numItemsToRemove)
		{
			// no resize or moves needed
		}
		else if (numItemsToInsert >= numItemsToRemove)
		{
			size_t delta = numItemsToInsert - numItemsToRemove;

			if (_length + delta > _capacity) extend(arena, cast(uint)delta);

			foreach_reverse(i; at + numItemsToRemove.._length)
			{
				this[i + delta] = this[i];
			}

			_length += delta;
		}
		else
		{
			size_t delta = numItemsToRemove - numItemsToInsert;

			foreach(i; at + numItemsToRemove.._length)
			{
				this[i - delta] = this[i];
			}

			_length -= delta;
		}
	}

	void unput(size_t numItems)
	{
		_length = cast(uint)(_length - numItems);
	}

	void reserve(ref ArrayArena arena, uint howMany)
	{
		if (_length + howMany > _capacity) extend(arena, howMany);
	}

	// returns memory to arena and zeroes the length
	void free(ref ArrayArena arena) {
		scope(exit) {
			externalArray = null;
			_length = 0;
			_capacity = NUM_INLINE_ITEMS;
		}
		static if (NUM_INLINE_ITEMS > 0)
			if (_capacity == NUM_INLINE_ITEMS)
				return; // noop

		if (capacity <= NUM_ITEMS_PER_PAGE) {
			size_t byteCapacity = nextPOT(_capacity * T.sizeof);
			ubyte[] oldBlock = (cast(ubyte*)externalArray)[0..byteCapacity];
			arena.freeBlock(oldBlock);
			return;
		}

		size_t numPages = _capacity / NUM_ITEMS_PER_PAGE;
		foreach(T* chunk; chunkedArray[0..numPages])
		{
			// free each page
			ubyte* chunkPtr = cast(ubyte*)chunk;
			ubyte[] page = chunkPtr[0..ARRAY_PAGE_BYTES];
			arena.freeBlock(page);
		}

		// free page array
		ubyte* arrayPtr = cast(ubyte*)chunkedArray;
		size_t pageArrayCapacity = nextPOT(numPages);
		ubyte[] pageArray = arrayPtr[0..pageArrayCapacity * (ubyte*).sizeof];
		arena.freeBlock(pageArray);
	}

	// extend the storage
	private void extend(ref ArrayArena arena, uint items)
	{
		uint byteCapacityNeeded = cast(uint)nextPOT((_length + items) * T.sizeof);
		void allocPages(T[] oldItems) {
			size_t numPages = byteCapacityNeeded / ARRAY_PAGE_BYTES;
			ubyte[] pageArray = arena.allocBlock(nextPOT(numPages * (ubyte*).sizeof));
			T** newChunkedArray = cast(T**)pageArray.ptr;
			foreach(i; 0..numPages) {
				ubyte[] page = arena.allocBlock(ARRAY_PAGE_BYTES);
				newChunkedArray[i] = cast(T*)page.ptr;
			}
			newChunkedArray[0][0..oldItems.length] = oldItems;
			chunkedArray = newChunkedArray;
			_capacity = cast(uint)(numPages * NUM_ITEMS_PER_PAGE);
		}
		//writefln("extend %s", _capacity);
		if (_capacity == NUM_INLINE_ITEMS) {
			if (byteCapacityNeeded <= ARRAY_PAGE_BYTES) {
				ubyte[] newBlock = arena.allocBlock(max(byteCapacityNeeded, MIN_EXTERNAL_BYTES));
				static if (NUM_INLINE_ITEMS > 0) {
					ubyte[] oldBlock = cast(ubyte[])inlineItems[];
					newBlock[0..oldBlock.length] = oldBlock;
				}
				externalArray = cast(T*)newBlock.ptr;
				_capacity = cast(uint)(newBlock.length / T.sizeof);
			} else {
				allocPages(inlineItems);
			}
			//writefln("  1 cap %s", _capacity);
		} else if (_capacity < NUM_ITEMS_PER_PAGE) {
			if (byteCapacityNeeded <= ARRAY_PAGE_BYTES) {
				size_t byteCapacity = nextPOT(_capacity * T.sizeof);
				ubyte[] block = (cast(ubyte*)externalArray)[0..byteCapacity];
				resizeSmallArray(arena, block, byteCapacityNeeded);
				externalArray = cast(T*)block.ptr;
				_capacity = cast(uint)(block.length / T.sizeof);
				//writefln("  2 cap %s", _capacity);
			} else {
				size_t byteCapacity = nextPOT(_capacity * T.sizeof);
				ubyte[] oldBlock = (cast(ubyte*)externalArray)[0..byteCapacity];
				allocPages(externalArray[0.._capacity]);
				arena.freeBlock(oldBlock);
			}
		} else if (_capacity == NUM_ITEMS_PER_PAGE) {
			assert(nextPOT(_capacity * T.sizeof) == ARRAY_PAGE_BYTES);
			uint pagesNeeded = divCeil(_length + items, NUM_ITEMS_PER_PAGE);
			ubyte[] pageArray = arena.allocBlock(nextPOT(pagesNeeded * (ubyte*).sizeof));
			T** newChunkedArray = cast(T**)pageArray.ptr;
			newChunkedArray[0] = externalArray;
			foreach(i; 1..pagesNeeded) {
				ubyte[] page = arena.allocBlock(ARRAY_PAGE_BYTES);
				newChunkedArray[i] = cast(T*)page.ptr;
			}
			chunkedArray = newChunkedArray;
			_capacity = pagesNeeded * NUM_ITEMS_PER_PAGE;
			//writefln("  3 cap %s", _capacity);
		} else {
			size_t numPages = _capacity / NUM_ITEMS_PER_PAGE;
			size_t pageArrayCapacity = nextPOT(numPages);
			size_t pagesNeeded = divCeil(_length + items, NUM_ITEMS_PER_PAGE);
			size_t pageArrayCapacityNeeded = nextPOT(pagesNeeded);
			if (pageArrayCapacityNeeded != pageArrayCapacity) {
				// extend page array
				ubyte[] pageArray = cast(ubyte[])(chunkedArray[0..pageArrayCapacity]);
				assert(pageArray.length < ARRAY_PAGE_BYTES);
				resizeSmallArray(arena, pageArray, pageArrayCapacityNeeded * (ubyte*).sizeof);
				chunkedArray = cast(T**)pageArray;
			}
			//writefln("extend pages %s -> %s", numPages, pagesNeeded);
			foreach(i; numPages..pagesNeeded) {
				ubyte[] page = arena.allocBlock(ARRAY_PAGE_BYTES);
				chunkedArray[i] = cast(T*)page.ptr;
				_capacity += NUM_ITEMS_PER_PAGE;
			}
			//writefln("  4 cap %s", _capacity);
		}
	}

	// Doubles the size of block
	private void resizeSmallArray(ref ArrayArena arena, ref ubyte[] oldBlock, size_t newLength) {
		assert(isPowerOfTwo(oldBlock.length));
		assert(oldBlock.length >= ArrayArena.MIN_BLOCK_BYTES);
		assert(oldBlock.length <= ARRAY_PAGE_BYTES);
		assert(newLength >= ArrayArena.MIN_BLOCK_BYTES, "too small");
		assert(newLength <= ARRAY_PAGE_BYTES, "too big");

		ubyte[] newBlock = arena.allocBlock(newLength);
		newBlock[0..oldBlock.length] = oldBlock;
		arena.freeBlock(oldBlock);
		oldBlock = newBlock;
	}

	int opApply(scope int delegate(size_t, ref T) dg) {
		size_t index;
		foreach (ref T item; this) {
			if (int res = dg(index, item))
				return res;
			++index;
		}
		return 0;
	}

	int opApply(scope int delegate(ref T) dg) {
		static if (NUM_INLINE_ITEMS > 0) {
			if (_capacity == NUM_INLINE_ITEMS) {
				foreach (ref T item; inlineItems[0.._length])
					if (int res = dg(item))
						return res;
				return 0;
			}
		}

		if (_capacity <= NUM_ITEMS_PER_PAGE)
		{
			foreach (ref T item; externalArray[0.._length])
				if (int res = dg(item))
					return res;
			return 0;
		}

		size_t numPages = _capacity / NUM_ITEMS_PER_PAGE;
		size_t itemsLeft = _length;
		foreach (i, T* subArray; chunkedArray[0..numPages])
		{
			size_t blockLength = min(itemsLeft, NUM_ITEMS_PER_PAGE);
			foreach (ref T item; subArray[0..blockLength])
				if (int res = dg(item))
					return res;
			itemsLeft -= blockLength;
		}
		return 0;
	}

	auto opSlice()
	{
		return ArrayItemRange!T(&this, 0, length);
	}

	auto opSlice(size_t from, size_t to)
	{
		return this[][from..to];
	}

	void removeInPlace(size_t at)
	{
		if (at+1 != _length)
		{
			this[at] = this[_length-1];
		}
		--_length;
	}

	void removeByShift(size_t at, size_t numToRemove = 1)
	{
		size_t to = at;
		size_t from = at + numToRemove;
		while(from < _length)
		{
			this[to] = this[from];
			++to;
			++from;
		}
		_length -= numToRemove;
	}

	void toString(scope void delegate(const(char)[]) sink) {
		import std.format : formattedWrite;
		sink("[");
		size_t i;
		foreach(ref T item; opSlice()) {
			if (i > 0) sink(", ");
			sink.formattedWrite("%s", item);
			++i;
		}
		sink("]");
	}
}

struct ArrayItemRange(T)
{
	private Array!T* buf;
	size_t start;
	size_t length;

	alias opDollar = length;
	bool empty() { return length == 0; }
	ref T front() { return (*buf)[start]; }
	ref T back() { return (*buf)[start+length-1]; }
	void popFront() { ++start; --length; }
	void popBack() { --length; }
	auto save() { return this; }
	ref T opIndex(size_t at) { return (*buf)[start + at]; }

	auto opSlice(size_t from, size_t to)
	{
		if (from != to)
		{
			assert(from < length);
			assert(to <= length);
		}
		size_t len = to - from;
		return ArrayItemRange(buf, start+from, len);
	}
}
