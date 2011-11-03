#ifndef _UTILS_QUEUE_H
#define _UTILS_QUEUE_H

#include <stdbool.h>

struct _Bag;
typedef struct _Bag Bag;

/** Create a new Bag. */
Bag * Bag_new(bool thread_safe);

/** Free the Bag. Note: the bag must be empty or memory will be leaked. */
void Bag_free(Bag * bag);

/**
	Try to add data to the bag. This can fail if there isn't enough memory.

	NOTE: this invalidates any iterators.

	@return Whether or not the add was successful.
*/
bool Bag_add(Bag * bag, void * data);

/** Treat this as an opaque type that can only be passed to Bag functions and compared for equality with other iterators. */
typedef void * Bag_iterator;

/** This function MUST be called before using any other iterator-related function. */
void Bag_start_iteration(Bag * bag);

/** The function MUST be called when done with iterator-related functions. Note that it invalidates any existing iterators. */
void Bag_stop_iteration(Bag * bag);

/** @return an iterator pointing to the first element in the bag, or Bag_end(bag) if the bag is empty. */
Bag_iterator Bag_begin(Bag * bag);

/** @return an iterator pointing one past the last element in the bag. */
inline Bag_iterator Bag_end(Bag * bag) { return NULL; }

/** @return an iterator to the next element in the set, or Bag_end(bag) if there are not more elements. */
Bag_iterator Bag_iterator_next(Bag * bag, Bag_iterator iterator);

/** @return the element pointed to by iterator. */
void * Bag_get(Bag * bag, Bag_iterator iterator);

/**
	Remove the element pointed to by iterator from the bag.

	NOTE: Bag_get(bag, iterator) MUST be called and its return value MUST be stored or free'd before calling Bag_erase(bag, iterator), or memory will be leaked.

	NOTE: This function invalidates all iterators except the one it returns.

	@return the same iterator that would have been returned by Bag_iterator_next(bag, iterator) if Bag_erase hadn't been called.
*/
Bag_iterator Bag_erase(Bag * bag, Bag_iterator iterator);

#endif
