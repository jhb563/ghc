/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team 1998-2006
 *
 * Generational garbage collector
 *
 * Documentation on the architecture of the Garbage Collector can be
 * found in the online commentary:
 * 
 *   http://hackage.haskell.org/trac/ghc/wiki/Commentary/Rts/Storage/GC
 *
 * ---------------------------------------------------------------------------*/

#ifndef GC_H
#define GC_H

#include "OSThreads.h"

/* -----------------------------------------------------------------------------
   General scheme
   
   ToDo: move this to the wiki when the implementation is done.

   We're only going to try to parallelise the copying GC for now.  The
   Plan is as follows.

   Each thread has a gc_thread structure (see below) which holds its
   thread-local data.  We'll keep a pointer to this in a thread-local
   variable, or possibly in a register.

   In the gc_thread structure is a step_workspace for each step.  The
   primary purpose of the step_workspace is to hold evacuated objects;
   when an object is evacuated, it is copied to the "todo" block in
   the thread's workspace for the appropriate step.  When the todo
   block is full, it is pushed to the global step->todos list, which
   is protected by a lock.  (in fact we intervene a one-place buffer
   here to reduce contention).

   A thread repeatedly grabs a block of work from one of the
   step->todos lists, scavenges it, and keeps the scavenged block on
   its own ws->scavd_list (this is to avoid unnecessary contention
   returning the completed buffers back to the step: we can just
   collect them all later).

   When there is no global work to do, we start scavenging the todo
   blocks in the workspaces.  This is where the scan_bd field comes
   in: we can scan the contents of the todo block, when we have
   scavenged the contents of the todo block (up to todo_bd->free), we
   don't want to move this block immediately to the scavd_list,
   because it is probably only partially full.  So we remember that we
   have scanned up to this point by saving the block in ws->scan_bd,
   with the current scan pointer in ws->scan.  Later, when more
   objects have been copied to this block, we can come back and scan
   the rest.  When we visit this workspace again in the future,
   scan_bd may still be the same as todo_bd, or it might be different:
   if enough objects were copied into this block that it filled up,
   then we will have allocated a new todo block, but *not* pushed the
   old one to the step, because it is partially scanned.

   The reason to leave scanning the todo blocks until last is that we
   want to deal with full blocks as far as possible.
   ------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   Step Workspace
  
   A step workspace exists for each step for each GC thread. The GC
   thread takes a block from the todos list of the step into the
   scanbd and then scans it.  Objects referred to by those in the scan
   block are copied into the todo or scavd blocks of the relevant step.
  
   ------------------------------------------------------------------------- */

typedef struct step_workspace_ {
    step * stp;			// the step for this workspace 
    struct gc_thread_ * gct;    // the gc_thread that contains this workspace

    // block that is currently being scanned
    bdescr *     scan_bd;
    StgPtr       scan;               // the scan pointer

    // where objects to be scavenged go
    bdescr *     todo_bd;
    bdescr *     buffer_todo_bd;     // buffer to reduce contention
                                     // on the step's todos list

    // where large objects to be scavenged go
    bdescr *     todo_large_objects;

    // Objects that need not be, or have already been, scavenged.
    bdescr *     scavd_list;
    lnat         n_scavd_blocks;     // count of blocks in this list

} step_workspace;

/* ----------------------------------------------------------------------------
   GC thread object

   Every GC thread has one of these. It contains all the step specific
   workspaces and other GC thread loacl information. At some later
   point it maybe useful to move this other into the TLS store of the
   GC threads
   ------------------------------------------------------------------------- */

typedef struct gc_thread_ {
#ifdef THREADED_RTS
    OSThreadId id;                 // The OS thread that this struct belongs to
    Mutex      wake_mutex;
    Condition  wake_cond;          // So we can go to sleep between GCs
    rtsBool    wakeup;
    rtsBool    exit;
#endif
    nat thread_index;              // a zero based index identifying the thread

    step_workspace ** steps;	   // 2-d array (gen,step) of workspaces

    bdescr * free_blocks;          // a buffer of free blocks for this thread
                                   //  during GC without accessing the block
                                   //   allocators spin lock. 

    lnat gc_count;                 // number of gc's this thread has done

    // --------------------
    // evacuate flags

    step *evac_step;               // Youngest generation that objects
                                   // should be evacuated to in
                                   // evacuate().  (Logically an
                                   // argument to evacuate, but it's
                                   // static a lot of the time so we
                                   // optimise it into a per-thread
                                   // variable).

    rtsBool failed_to_evac;        // failue to evacuate an object typically 
                                   //  causes it to be recorded in the mutable 
                                   //  object list

    rtsBool eager_promotion;       // forces promotion to the evac gen
                                   // instead of the to-space
                                   // corresponding to the object

    lnat thunk_selector_depth;     // ummm.... not used as of now

} gc_thread;

extern nat N;
extern rtsBool major_gc;

extern gc_thread *gc_threads;
register gc_thread *gct __asm__("%rbx");
// extern gc_thread *gct;  // this thread's gct TODO: make thread-local

extern StgClosure* static_objects;
extern StgClosure* scavenged_static_objects;

extern bdescr *mark_stack_bdescr;
extern StgPtr *mark_stack;
extern StgPtr *mark_sp;
extern StgPtr *mark_splim;

extern rtsBool mark_stack_overflowed;
extern bdescr *oldgen_scan_bd;
extern StgPtr  oldgen_scan;

extern long copied;
extern long scavd_copied;

#ifdef THREADED_RTS
extern SpinLock static_objects_sync;
#endif

#ifdef DEBUG
extern nat mutlist_MUTVARS, mutlist_MUTARRS, mutlist_MVARS, mutlist_OTHERS;
#endif

StgClosure * isAlive(StgClosure *p);

#endif /* GC_H */
