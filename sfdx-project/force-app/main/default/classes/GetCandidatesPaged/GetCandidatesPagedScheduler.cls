/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesPagedScheduler: Scheduler Apex class that enqueues a new job for the
*   GetCandidatesPaged class.
*
*   When callouts from GetCandidatesPaged class fail or a certain stack depth is reached, 
*   a new job needsto be made. This class allows scheduling those new jobs to run some time in the 
*   future, so as to not repeatedly attempt failed callouts one right after another, and to break
*   up chains, resetting the stack depth and avoiding throttling limits or stack depth exceptions.
*
* Constructor:
*     - public GetCandidatesPagedScheduler(
*       GetCandidatesPaged.PagingAggregator aggregator, Integer startFrom,
*       Integer pageSize, Integer attempt, Boolean faulty, CandidatesCallout.Sizes size)
*
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.1
* @created        2022-06-16
* @modified       2022-06-16
* @systemLayer    Asynchronous/Schedulable
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
*   2022-06-24 (v1.1): Minor changes to constructor and calling the Queueable class to accomodate
*       changes in other classes.
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class GetCandidatesPagedScheduler implements Schedulable {

    //  CLASS VARIABLES
    private GetCandidatesPaged.PagingAggregator aggregator;
    private final Integer startFrom;
    private final Integer pageSize;
    private final Integer attempt;
    private final Boolean faulty;
    private final CandidatesCallout.Sizes size;

    //  CONSTRUCTOR
    public GetCandidatesPagedScheduler(
        GetCandidatesPaged.PagingAggregator aggregator, Integer startFrom, 
        Integer pageSize, Integer attempt, Boolean faulty, CandidatesCallout.Sizes size
    ) {
        this.aggregator = aggregator;
        this.startFrom = startFrom;
        this.pageSize = pageSize;
        this.attempt = attempt;
        this.faulty = faulty;
        this.size = size;
    }

    public void execute(SchedulableContext ctx) {
        /*
        * Create a new job at making a callout from GetCandidatesPaged class,
        * getting the information passed from the previous job, then enqueue it with a depth value
        * of 1 (this always starts a new chain)
        */
        GetCandidatesPaged nextAttempt = new GetCandidatesPaged(
            this.aggregator, this.startFrom, this.pageSize, this.attempt, 1, this.faulty, this.size
        );
        System.enqueueJob(nextAttempt);
    }
}