# Producer:
#
# The idea is to keep the specified number of threads filled with tasks to
# maximize parallelism (only works for IO and external processes).
#
# Go down the task depend tree mapping prereq tasks to their parent(s).
# When a task has no children that need execution add it to queue.
# At the end of every task execution, check its parents to see if the parents
# can be added to the queue.  If the parents prereqs are all uptodate add to
# queue.
#
# Consumer:
#
# Implement n threads, take tasks from single queue.  Queue deque() blocks
# threads when empty waiting for main thread to add more tasks.  Returns nil if
# no more tasks are available.
#
require 'thread'

# Similar to Queue but has a 'done' function for
# removing all tasks from the queue and letting
# consumer threads know there is no more tasks.
class TaskQueue
  def initialize
    @mutex = Mutex.new
    @resource = ConditionVariable.new
    @tasks = []
    @done = false
  end

  # Add an item to the queue.
  def enq item
    @mutex.synchronize {
      if not @done
        @tasks << item
        @resource.signal
      end
      not @done
    }
  end

  # Empty Queue and unblock threads waiting on 'deq'
  def done
    @mutex.synchronize {
      @done = true
      @tasks.clear
      @resource.broadcast
    }
  end

  # Remove an item from the queue.
  # Block if no item is available right now.
  # If 'done' is called, unblock and return nil.
  def deq
    @mutex.synchronize {
      while @tasks.empty? and not @done
        @resource.wait(@mutex)
      end
      @tasks.pop
    }
  end
end

module Rake
  class Application
    def top_level
      standard_exception_handling do
        if options.show_tasks
          display_tasks_and_comments
        elsif options.show_prereqs
          display_prerequisites
        else
          num_threads = ENV['threads'] ? ENV['threads'].to_i : 1
          top_level_tasks.each { |task_name|
            task = self[task_name]
	    if num_threads > 1
              parallel_invoke(task, num_threads)
            else
              task.invoke
            end
          }
        end
      end
    end

    # Run parallel tasks in fixed number of threads
    def parallel_invoke(task, num_threads)
      @task_queue = TaskQueue.new
      result_queue = TaskQueue.new
      thread_error = nil
      lock = Mutex.new
      threads = (1..num_threads).collect { |x|
        Thread.new {
          while t = @task_queue.deq
            begin
              t.invoke
              result_queue.enq t
            rescue
              # Make sure we drain the queue for other threads so that they
              # don't continue invoking prereqs.  This helps make the error
              # messages easier to see, otherwise the other threads will
              # continue building prereqs until they encounter errors.
              @task_queue.done

              # Let main thread know we are done.
              result_queue.done
		   
              # Block the exception but save for later.  This allows other
	      # threads to complete their current prereq, before we issue the
	      # error to the user, insuring that the rake formatted error is
              # the last line sent to the stdout/stderr.
              lock.synchronize do
                if not thread_error
                  thread_error = $!
                end
              end
            end
          end
        }
      }

      # Keep pulling task results from the queue, until we get to the root
      # target.
      # Remove non-root targets from the dependency graph
      #   (i.e. delete the relevent members in the children/parent hash maps)
      # If this results in any tasks with no children (i.e. no more prereqs
      # to execute)
      #   then submit that task to the thread pool for execution.
      @children = {} # maps task -> tasks it depends on 
      @parents  = {} # maps task -> tasks that depend on it
  
      analyze_dependencies(task)

      while (result = result_queue.deq) != nil && result != task
        @parents[result].each do |parent_task|
          list = @children[parent_task]
          list.delete result
          if list.empty?
            @children.delete parent_task
	    @task_queue.enq parent_task
          end
        end
    
        @parents.delete result
      end

      # We're done processing tasks at this stage.  Let threads know they can
      # finish.
      @task_queue.done
      threads.each { |t| t.join }

      if thread_error
        raise thread_error
      end
    end

    # Stores the relationship between the tasks involved in this 
    # build, using the "children" and "parents" hash tables
    def analyze_dependencies(task, analyzed=Array.new)
      return if analyzed.member?(task)
  
      analyzed << task
  
      prereqs = task.prerequisites
      if prereqs.empty?
        return if not @task_queue.enq task
      else
        prereqs.each do |child|
          child_task = self[child]
          (@children[task] ||= Array.new) << child_task
          (@parents[child_task] ||= Array.new) << task
          analyze_dependencies(child_task, analyzed)
        end
      end
    end
  end
end
