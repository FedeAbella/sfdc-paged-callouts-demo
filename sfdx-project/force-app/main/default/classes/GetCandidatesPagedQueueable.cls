/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesPagedQueueable: Queuable class for upserting Candidate records from Heroku endpoint
*                              via External ID, using paging to get the records in parts.
*
*   Queueable Apex class that makes callouts to a Heroku endpoint in a paged manner, getting
*   Candidate objects which are then upserted using External_ID__c as reference. The class
*   takes a starting index (1-based) and a page size, and retrieves that amount of records from the
*   endpoint. After processing, it enqueues or schedules a new job to get the next page. In case of 
*   any errors found during callout, new attempts at the same page are enqueued or scheduled, up to
*   a maximum number of allowed attempts defined in a Custom Metadata Type.
*
* Constructor:
*     - public GetCandidatesPagedQueueable(GetCandidatesPagedQueueable.PagingAggregator aggregator, 
*           Integer startFrom, Integer pageSize, Integer attempt, Integer depth)
*
* Methods:
*     - public void execute(QueueableContext ctx): Executes the callout and processes the upsert.
*           Handles whether a new attempt or a new page must be called
*     - private void logIntoAggregatorCallout(String message): Logs a received or success message
*           for each callout attempt made into the aggregator logbook
*     - private void logJobFinished(): Inserts a Developer_Log__c record upon finishing the entire
*           job, detailing the results
*     - private void logMaxAttemptsReachedError(Integer maxAttempts): Inserts a Developer_Log__c
*           record detailing that the maximum number of attempted callouts failed, thus ending the
*           job prematurely
*     - private void logMaxAttemptsExceededError(Integer maxAttempts): Inserts a Developer_Log__c
*           record detailing that an attempt was made that exceeds the maximum allowed attempts
*     - private String getAggregatorData(): Parses data saeved in the PagingAggregator into a
*           message string to be used in Developer_Log__c records
*     - private String getCronInFuture(Integer secondsIntoFuture): Returns a cron string 
*           corresponding to some number of seconds in the future from now.
*     - private void setUpNextAttempt(): Sets up enqueueing or scheduling a new attempt at making
*           a callout to a page when one has already failed.
*     - private void checkPagingAndMoveOnOrFinish(Integer receivedCandidates): Handles checking
*           whether a new page needs to be called for, or the last page has been reached, and either
*           enqueues or schedules a new job to do so.
*     - private void breakChainAndRestart(): Breaks chains of jobs that have reached stack depth of
*           5, by instead of enqueueing a job, scheduling one to be enqueued 5 seconds in the future
*     - private void cleanUpScheduledJobs(): Aborts previously ran scheduled jobs pertaining to new
*           attempts or breaking of chains, cleaning up the scheduled jobs section of setup.
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-16
* @modified       2022-06-16
* @systemLayer    Asynchronous/Queueable/Callouts
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class GetCandidatesPagedQueueable implements Queueable, Database.AllowsCallouts {
    
    /*
    * Aggregator class so we can keep track of aggregated results along multiple pages
    */
    public class PagingAggregator {
        public Integer aggregatedReceivedCandidates; //  Keep track of total candidates received
        public Integer aggregatedUpsertedCandidates; //  Keep track of total upserted candidates
        public Integer aggregatedInsertedCandidates; //  Keep track of total inserted candidates
        public Integer aggregatedUpdatedCandidates; //  Keep track of total updated candidates
        public Integer aggregatedErrorCandidates; //  Keep track of total candidates with errors
        public List<String> calloutsLogbook; //  Keep a logbook of callout attemps
        public List<String> upsertErrorLogbook; //  Keep a logbook of upsert errors across pages

        public PagingAggregator() {
            this.aggregatedReceivedCandidates = 0;
            this.aggregatedUpsertedCandidates = 0;
            this.aggregatedInsertedCandidates = 0;
            this.aggregatedUpdatedCandidates = 0;
            this.aggregatedErrorCandidates = 0;
            this.calloutsLogbook = new List<String>();
            this.upsertErrorLogbook = new List<String>();
        }
    }

    //  INSTANCE VARIABLES
    private PagingAggregator aggregator; //  The aggregator object used to keep track across pages
    private final Integer attempt; //  Current attempt number
    private final Integer startFrom; //  The element to start the page from
    private final Integer pageSize; //  The amount of elements to include in the current page
    private Integer depth; //  Keeps track of chain depth, so we can avoid throttling or max depth

    //  CONSTRUCTOR
    public GetCandidatesPagedQueueable(PagingAggregator aggregator, Integer startFrom,
        Integer pageSize, Integer attempt, Integer depth
    ) {
        this.aggregator = aggregator;
        this.startFrom = startFrom;
        this.pageSize = pageSize;
        this.attempt = attempt;
        this.depth = depth;
    }

    public void execute (QueueableContext ctx) {

        //  Get the current maximum allowed number of attempts
        Integer maxAttempts = (Integer)Callout_Setting__mdt.getInstance('Heroku_Datasource')
                                                            .Max_Paged_Attempts__c;
        /*
        * Prevent the job from running if the number of attempts is exceeded. Instead 
        * insert a Developer_Log__c record of type ERROR, clean up any scheduled job that were
        * created as previous attempts, and end the job
        */
        if (attempt > maxAttempts) {
            logMaxAttemptsExceededError(maxAttempts);
            cleanUpScheduledJobs();
            return;
        }

        //  Attempt the callout
        List<Candidate__c> candidateList;
        try {
            candidateList = CandidatesCallout.getCandidatesPaged(this.startFrom, this.pageSize);
        } catch (CandidatesCallout.CandidatesCalloutException e) {

            //  If we get any errors in callout, log it into the aggregator
            logIntoAggregatorCallout(
                e.getMessage()
            );

            /*
            * Check if we've got some attempts left. If so, run a new job some time in the future,
            * as defined in the Custom Metadata Type, increasing the attempt number by 1. 
            * Then finish the current job.
            */
            if (attempt < maxAttempts) {
                setUpNextAttempt();
                return;
            }

            /*
            * Otherwise, we've ran out of attempts. Create a Developer_Log__c record detailing this,
            * clean up any scheduled jobs that were created during previous failed attempts, and
            * finish this job.
            */
            logMaxAttemptsReachedError(maxAttempts);
            cleanUpScheduledJobs();
            return;
        }

        /*
        * If we get here, we've had a successful callout and received data (or an empty list)
        * in return. Log the correct callout into the aggregator, and clean up any scheduled jobs
        * remaining from previous failed attempts
        */
        logIntoAggregatorCallout('success');
        cleanUpScheduledJobs();

        /*
        * Check if we've received an empty list in response. If so, we've gone past the end last
        * page of data, and there's nothing left to do. Create a Developer_Log__c record detailing
        * this, and finish the job.
        */
        if (candidateList.isEmpty()) {
            logJobFinished();
            return;
        }

        /*
        * If we're here, then we've received some candidates back from the callout
        */
        //  Add the number of received candidates to the aggregator
        this.aggregator.aggregatedReceivedCandidates += candidateList.size();

        /*
        * This would be the place for some post-processing on the objects returned from the callout.
        * For simplicity's sake, in this demo we're just going to upsert those objects, but keep
        * track of received and upserted (created or updated) totals, as well as any errors found.
        */

        /*
        * Upsert the records using the External_ID__c field as identifier. Return any errors found,
        * but don't prevent those from upserting the correct ones
        */
        List<Database.UpsertResult> upsertResults = Database.upsert(
            candidateList, Candidate__c.Fields.External_ID__c, false
        );

        /*
        * Go over the results of the upsert, update running totals and keep a log of records that
        * failed the upsert, as well as their errors for final logging
        */
        for (Database.UpsertResult result : upsertResults) {
            if (!result.isSuccess()) {
                this.aggregator.aggregatedErrorCandidates += 1;
                String errorMessage = 'Errors during upsert: '
                    + JSON.serialize(
                        candidateList.get(
                            upsertResults.indexOf(result)
                        )
                    )
                    + '\n';
                for (Database.Error error : result.getErrors()) {
                    errorMessage += error.getStatusCode()
                        + ':' + error.getFields()
                        + ':' + error.getMessage()
                        + '\n';
                }
                this.aggregator.upsertErrorLogbook.add(errorMessage);
            } else {
                this.aggregator.aggregatedUpsertedCandidates += 1;
                if (result.isCreated()) {
                    this.aggregator.aggregatedInsertedCandidates += 1;
                } else {
                    this.aggregator.aggregatedUpdatedCandidates += 1;
                }
            }
        }

        /*
        * After we're done with all the processing, check whether we should move onto a new page
        * or if the job is complete. The finish the current job.
        */
        checkPagingAndMoveOnOrFinish(candidateList.size());
        return;
    }   

    //  HELPER METHODS

    /*
    * Logs a message into the paging aggregator's callout logbook
    */
    private void logIntoAggregatorCallout(String message) {
        System.JSONGenerator gen = JSON.createGenerator(false);
        gen.writeStartObject();
        gen.writeNumberField('startFrom', this.startFrom);
        gen.writeNumberField('endAt', this.startFrom + this.pageSize - 1);
        gen.writeNumberField('attempt', this.attempt);
        gen.writeStringField('message', message);
        gen.close();

        this.aggregator.calloutsLogbook.add(
            gen.getAsString()
        );
    }

    /*
    * Insert a Developer_Log__c record of type INFO or WARNING (if any database errors were found
    * during upsert) informing the entire paging job has finished. Include the aggregated data.
    */
    private void logJobFinished() {
        DeveloperLogHandler.LogType logType = this.aggregator.upsertErrorLogbook.isEmpty() ? 
                                              DeveloperLogHandler.LogType.INFO :
                                              DeveloperLogHandler.LogType.WARNING;
        DeveloperLogHandler.createDevLog(
            logType, 
            'Get Candidates Paged Complete: ' + System.now(), 
            'GetCandidatesPagedQueueable class has completed the job.\n\n'
            + getAggregatorData()
        );
    }

    /*
    * Insert a DeveloperLog__c record of type ERROR warning that the maximum number of allowed
    * attempts was reached. Include the aggregator data received thus far before the error.
    */
    private void logMaxAttemptsReachedError(Integer maxAttempts) {
        DeveloperLogHandler.createDevLog(
            DeveloperLogHandler.LogType.ERROR, 
            'Get Candidates Paged Max Attempts Reached: ' + System.now(), 
            'GetCandidatesPagedQueueable class has reached the maximum number of allowed attempts. '
            + 'Max attempts allowed: ' + maxAttempts + '\n\n'
            + 'Before the error was reached:\n\n'
            + getAggregatorData()
        );
    }

    /*
    * Insert a Developer_Log__c record of type ERROR warning of the max attempts allowed being
    * exceeded. Include the aggregator data received thus far before the error.
    */
    private void logMaxAttemptsExceededError(Integer maxAttempts) {
        DeveloperLogHandler.createDevLog(
            DeveloperLogHandler.LogType.ERROR, 
            'Get Candidates Paged Exception: ' + System.now(), 
            'GetCandidatesPagedQueueable class exceeded maximum number of allowed attempts. ' 
            + 'Attempt number: ' + this.attempt + '. Max attempts allowed: ' + maxAttempts + '\n\n'
            + 'Before the error was reached:\n\n'
            + getAggregatorData()
        );
    }

    /*
    * Get the data stored in the aggregator object in a formatted string, to be used in 
    * Developer_Log__c records to be inserted, informing of success or failure of callout
    */
    private String getAggregatorData() {
        String aggregatedData = 
        'Received Candidates: ' + this.aggregator.aggregatedReceivedCandidates + '\n'
        + 'Upserted Candidates: ' + this.aggregator.aggregatedUpsertedCandidates + '\n'
        + 'Inserted Candidates: ' + this.aggregator.aggregatedInsertedCandidates + '\n'
        + 'Updated Candidates: ' + this.aggregator.aggregatedUpdatedCandidates + '\n'
        + 'Candidates with Errors: ' + this.aggregator.aggregatedErrorCandidates + '\n\n'
        + ((this.aggregator.upsertErrorLogbook.isEmpty()) ? 
            '' :
            'Database Error logbook:\n' + String.join(this.aggregator.upsertErrorLogbook, '\n\n')
          )
        + 'Callouts logbook:\n\n' + String.join(this.aggregator.calloutsLogbook, '\n');

        return aggregatedData;
    }

    /*
    * Gets a cron string some number of seconds into the future from now. Used to schedule a new
    * paging callout to be continued in the future when a callout fails.
    */
    private String getCronInFuture(Integer secondsIntoFuture) {
        Datetime futureMoment = System.now().addSeconds(secondsIntoFuture);
        String seconds = String.valueOf(futureMoment.second());
        String minutes = String.valueOf(futureMoment.minute());
        String hour = String.valueOf(futureMoment.hour());
        String day = String.valueOf(futureMoment.day());
        String month = String.valueOf(futureMoment.month());
        String year = String.valueOf(futureMoment.year());

        String cron = seconds + ' ' + minutes + ' ' + hour + ' ' + day + ' ' + month + ' ? ' + year;
        return cron;
    }

    /*
    * Sets up the next attempt after a failed callout, if there are any attempts left. 
    * Checks the delay between attempts set up in Custom Metadata Type: If delay is 0, enqueue a new
    * job immediately, unless the stack depth is already 5. Otherwise, schedule a new one in 
    * the future.
    */
    private void setUpNextAttempt() {
        //  Get the setup delay between attempts
        Integer delay = (Integer) Callout_Setting__mdt.getInstance('Heroku_Datasource')
                                                      .Delay_Between_Attempts__c;

        //  If we've set up no delay and can still chain new jobs, enqueue one immediately
        if (delay <= 0 && this.depth < 5) {
            GetCandidatesPagedQueueable nextAttempt = new GetCandidatesPagedQueueable(
                this.aggregator, this.startFrom, this.pageSize, this.attempt + 1, this.depth + 1
            );
            //  Only enqueue a new attempt if it's not a Test, as chaining is not allowed in tests
            if (!Test.isRunningTest()) {
                System.enqueueJob(nextAttempt);
            }
            return;
        }
        //  If we've set up no delay but are already at depth 5, instead break the chain
        if (delay <= 0) {
            breakChainAndRestart(this.aggregator, this.startFrom, this.pageSize, this.attempt + 1);
            return;
        }

        //  If there's some delay set up between attempts, schedule a new job to run in the future
        String cron = getCronInFuture(delay);
        GetCandidatesPagedQueueableScheduler nextFutureAttempt = 
            new GetCandidatesPagedQueueableScheduler(
                this.aggregator, this.startFrom, this.pageSize, this.attempt + 1
        );
        System.schedule(
            'GetCandidatesPagedQueueable attempt ' + this.attempt + 1 + ' ' + cron, 
            cron, 
            nextFutureAttempt
        );
    }

    /*
    * Check if the number of received candidates is less than the page size. If so, then the last
    * page has been reached, and no more callouts should be made. Log that the job has finished.
    * If as many candidates were received as those requested, there may be more in future pages,
    * so immediately enqueue getting the next page if the stack depth is less than 5. If the stack
    * depth has reached 5, instead break the chain and schedule to continue it a bit in the future.
    */
    private void checkPagingAndMoveOnOrFinish(Integer receivedCandidates) {
        if (receivedCandidates == this.pageSize && this.depth < 5) {
            GetCandidatesPagedQueueable nextPage = new GetCandidatesPagedQueueable(
                this.aggregator, this.startFrom + this.pageSize, this.pageSize, 1, this.depth + 1
            );
            //  Only enqueue the job if we're not running tests, as chaining is not allowed in tests
            if (!Test.isRunningTest()) {
                System.enqueueJob(nextPage);
            }
            return;
        }

        if (receivedCandidates == this.pageSize) {
            breakChainAndRestart(this.aggregator, this.startFrom + this.pageSize, this.pageSize, 1);
            return;
        }

        logJobFinished();
        return;
    } 

    /*
    * Depending on org type, chained queueables can either have a maximum stack depth of 5, or they
    * can have infinite depth, but execution will be throttled by Salesforce after a stack depth of
    * 5 anyways. In order to bypass both of this limits, we break the chain of queueables whenever
    * we reach a stack depth of 5. In that case, instead of enqueuing a new job immediately, we
    * schedule a new job to be enqueued 5 seconds into the future, resetting the stack depth.
    */
    private void breakChainAndRestart(PagingAggregator aggregator, Integer startFrom,
        Integer pageSize, Integer attempt
    ) {
        String cron = getCronInFuture(5);
        GetCandidatesPagedQueueableScheduler futureJob = 
            new GetCandidatesPagedQueueableScheduler(aggregator, startFrom, pageSize, attempt);
        System.schedule(
            'GetCandidatesPagedQueueable attempt ' + attempt + ' ' + cron, 
            cron, 
            futureJob
        );
    }

    /*
    * Clean up any scheduled jobs that were created during previous failed callouts
    */
    private void cleanUpScheduledJobs(){
        /*
        * Get a list of all scheduled job that have a name as those we set on this class for future
        * attempts, that have already ran once, and are not scheduled to run again.
        */
        List<CronTrigger> previousJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.JobType = '7'
            AND CronJobDetail.Name LIKE 'GetCandidatesPagedQueueable attempt%'
            AND NextFireTime = NULL
            AND TimesTriggered = 1
        ];

        for (CronTrigger job : previousJobs) {
            System.abortJob(job.Id);
        }
    }
}