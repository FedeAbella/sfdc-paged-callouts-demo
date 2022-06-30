/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesPaged: Queuable class for upserting Candidate records from Heroku endpoint
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
*     - public GetCandidatesPaged(GetCandidatesPaged.PagingAggregator aggregator, 
*           Integer startFrom, Integer pageSize, Integer attempt, Integer depth,
*           Boolean faulty, CandidatesCallout.Sizes size)
*
* Methods:
*     - public void execute(QueueableContext ctx): Executes the callout and processes the upsert.
*           Handles whether a new attempt or a new page must be called
*     - private void logAggregatorCallout(String message): Logs a received or success message
*           for each callout attempt made into the aggregator logbook
*     - private void logJobFinished(): Inserts a Developer_Log__c record upon finishing the entire
*           job, detailing the results
*     - private void logMaxAttemptsReached(Integer maxAttempts): Inserts a Developer_Log__c
*           record detailing that the maximum number of attempted callouts failed, thus ending the
*           job prematurely
*     - private void logMaxAttemptsExceeded(Integer maxAttempts): Inserts a Developer_Log__c
*           record detailing that an attempt was made that exceeds the maximum allowed attempts
*     - private String getAggregatorData(): Parses data saeved in the PagingAggregator into a
*           message string to be used in Developer_Log__c records
*     - private String getCronInFuture(Integer secondsIntoFuture): Returns a cron string 
*           corresponding to some number of seconds in the future from now.
*     - private void setUpNextAttempt(): Sets up enqueueing or scheduling a new attempt at making
*           a callout to a page when one has already failed.
*     - private Integer getDelayBetweenAttempts(): Returns the delay set in Custom Metadata Types to
*           be left between failed callout attempts. If we're running a test, instead receive a
*           value set in TestUtils
*     - private void checkPaging(Integer receivedCandidates): Handles checking
*           whether a new page needs to be called for, or the last page has been reached, and either
*           enqueues or schedules a new job to do so.
*     - private void breakChainAndRestart(): Breaks chains of jobs that have reached stack depth of
*           5, by instead of enqueueing a job, scheduling one to be enqueued 5 seconds in the future
*     - private void cleanUpScheduledJobs(): Aborts previously ran scheduled jobs pertaining to new
*           attempts or breaking of chains, cleaning up the scheduled jobs section of setup.
*     - private void manageAggregatorSize(): Check the estimated heap size taken by the
*           PagingAggregator, and compare it to a fraction of limit heap size, as defined in custom
*           metadata type. If it's larger, flush the data into a Developer_Log__c record, and
*           reinstantiate a new empty PagingAggregator
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        3.0
* @created        2022-06-16
* @modified       2022-06-29
* @systemLayer    Asynchronous/Queueable/Callouts
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
*   2022-06-24 (v2.0): Changes made to accomodate being able to call a faulty endpoint, and using
*       CandidatesCallout.Sizes Enum to determine max number of rows to retrieve.
*   2022-06-29 (v3.0): Added handling the PagingAggregator size possibly taking a large size, thus
*       flushing the results and reinstantiating to avoid heap size limit exceptions
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class GetCandidatesPaged implements Queueable, Database.AllowsCallouts {
    
    /*
    * Aggregator class so we can keep track of aggregated results along multiple pages.
    * Because the aggregator is passed along instances of the Queueable class, and keeps growing
    * in size as more information is collected, we also keep an estimate of the total heap size
    * taken by the aggregator. This is most likely going to be dominated by the total size of string
    * values written into logbooks, so this is used as the main first-order estimation. Along the
    * code, every string added to one of the logbooks is counted as its length() times 2 bytes (as
    * each Unicode character takes 16-bits)
    */
    public class PagingAggregator {
        public Integer aggReceived; //  Keep track of total candidates received
        public Integer aggUpserted; //  Keep track of total upserted candidates
        public Integer aggInserted; //  Keep track of total inserted candidates
        public Integer aggUpdated; //  Keep track of total updated candidates
        public Integer aggWithError; //  Keep track of total candidates with errors
        public Integer estHeapSize; //  An estimate of total heap size taken by this object
        public List<String> callsLogbook; //  Keep a logbook of callout attemps
        public List<String> errorLogbook; //  Keep a logbook of upsert errors across pages

        public PagingAggregator() {
            this.aggReceived = 0;
            this.aggUpserted = 0;
            this.aggInserted = 0;
            this.aggUpdated = 0;
            this.aggWithError = 0;
            this.estHeapSize = 0;
            this.callsLogbook = new List<String>();
            this.errorLogbook = new List<String>();
        }
    }

    //  INSTANCE VARIABLES
    private PagingAggregator aggregator; //  The aggregator object used to keep track across pages
    private final Integer attempt; //  Current attempt number
    private final Integer startFrom; //  The element to start the page from
    private final Integer pageSize; //  The amount of elements to include in the current page
    private Integer depth; //  Keeps track of chain depth, so we can avoid throttling or max depth
    private Boolean faulty; //  Whether we're calling the standard endpoint or a faulty one
    private CandidatesCallout.Sizes size; // The size of data we're getting

    //  CONSTRUCTOR
    public GetCandidatesPaged(PagingAggregator aggregator, Integer startFrom,
        Integer pageSize, Integer attempt, Integer depth, Boolean faulty, 
        CandidatesCallout.Sizes size
    ) {
        this.aggregator = aggregator;
        this.startFrom = startFrom;
        this.pageSize = pageSize;
        this.attempt = attempt;
        this.depth = depth;
        this.faulty = faulty;
        this.size = size;
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
            logMaxAttemptsExceeded(maxAttempts);
            cleanUpScheduledJobs();
            return;
        }

        //  Attempt the callout
        List<Candidate__c> candidateList;
        try {
            candidateList = CandidatesCallout.getCandidatesPaged(
                this.startFrom, this.pageSize, this.faulty, this.size
            );
        } catch (CandidatesCallout.CandidatesCalloutException e) {

            //  If we get any errors in callout, log it into the aggregator
            logAggregatorCallout(
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
            logMaxAttemptsReached(maxAttempts);
            cleanUpScheduledJobs();
            return;
        }

        /*
        * If we get here, we've had a successful callout and received data (or an empty list)
        * in return. Log the correct callout into the aggregator, and clean up any scheduled jobs
        * remaining from previous failed attempts
        */
        // logAggregatorCallout('success'); 
        /*
        * We can also add successful attempts to logbook for checking, but we're keeping it
        * commented here so the logbook is smaller and errors are more visible
        */
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
        this.aggregator.aggReceived += candidateList.size();

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
                this.aggregator.aggWithError += 1;
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
                this.aggregator.estHeapSize += errorMessage.length() * 2;
                this.aggregator.errorLogbook.add(errorMessage);
            } else {
                this.aggregator.aggUpserted += 1;
                if (result.isCreated()) {
                    this.aggregator.aggInserted += 1;
                } else {
                    this.aggregator.aggUpdated += 1;
                }
            }
        }

        /*
        * After we're done with all the processing, check whether we should move onto a new page
        * or if the job is complete. The finish the current job.
        */
        checkPaging(candidateList.size());
        return;
    }   

    //  HELPER METHODS

    /*
    * Logs a message into the paging aggregator's callout logbook
    */
    private void logAggregatorCallout(String message) {
        System.JSONGenerator gen = JSON.createGenerator(false);
        gen.writeStartObject();
        gen.writeNumberField('startFrom', this.startFrom);
        gen.writeNumberField('endAt', this.startFrom + this.pageSize - 1);
        gen.writeNumberField('attempt', this.attempt);
        gen.writeStringField('message', message);
        gen.close();

        this.aggregator.estHeapSize += gen.getAsString().length() * 2;
        this.aggregator.callsLogbook.add(
            gen.getAsString()
        );
    }

    /*
    * Insert a Developer_Log__c record of type INFO or WARNING (if any database errors were found
    * during upsert) informing the entire paging job has finished. Include the aggregated data.
    */
    private void logJobFinished() {
        DeveloperLogHandler.LogType logType = this.aggregator.errorLogbook.isEmpty() ? 
                                              DeveloperLogHandler.LogType.INFO :
                                              DeveloperLogHandler.LogType.WARNING;
        DeveloperLogHandler.createDevLog(
            logType, 
            'Get Candidates Paged Complete: ' + System.now(), 
            'GetCandidatesPaged class has completed the job.\n\n'
            + getAggregatorData()
        );
    }

    /*
    * Insert a DeveloperLog__c record of type ERROR warning that the maximum number of allowed
    * attempts was reached. Include the aggregator data received thus far before the error.
    */
    private void logMaxAttemptsReached(Integer maxAttempts) {
        DeveloperLogHandler.createDevLog(
            DeveloperLogHandler.LogType.ERROR, 
            'Get Candidates Paged Max Attempts Reached: ' + System.now(), 
            'GetCandidatesPaged class has reached the maximum number of allowed attempts. '
            + 'Max attempts allowed: ' + maxAttempts + '\n\n'
            + 'Before the error was reached:\n\n'
            + getAggregatorData()
        );
    }

    /*
    * Insert a Developer_Log__c record of type ERROR warning of the max attempts allowed being
    * exceeded. Include the aggregator data received thus far before the error.
    */
    private void logMaxAttemptsExceeded(Integer maxAttempts) {
        DeveloperLogHandler.createDevLog(
            DeveloperLogHandler.LogType.ERROR, 
            'Get Candidates Paged Exception: ' + System.now(), 
            'GetCandidatesPaged class exceeded maximum number of allowed attempts. ' 
            + 'Attempt number: ' + this.attempt + '. Max attempts allowed: ' + maxAttempts + '\n\n'
            + 'Before the error was reached:\n\n'
            + getAggregatorData()
        );
    }

    /*
    * Insert a Developer_Log__c record of type INFO, reporting the job needed to flush its
    * PagingAggregator results due to a large Aggregator size before continuing.
    */
    private void logPartialResult() {
        DeveloperLogHandler.createDevLog(
            DeveloperLogHandler.LogType.INFO, 
            'Get Candidates Paged Partial result: ' + System.now(),
            'GetCandidatesPaged class flushed partial result because of Aggregator Size:\n\n'
            + getAggregatorData()
            + '\n\nAggregator was reinitialized and job continued.'
        );
    }

    /*
    * Get the data stored in the aggregator object in a formatted string, to be used in 
    * Developer_Log__c records to be inserted, informing of success or failure of callout
    */
    private String getAggregatorData() {
        return 'Received Candidates: ' + this.aggregator.aggReceived + '\n'
        + 'Upserted Candidates: ' + this.aggregator.aggUpserted + '\n'
        + 'Inserted Candidates: ' + this.aggregator.aggInserted + '\n'
        + 'Updated Candidates: ' + this.aggregator.aggUpdated + '\n'
        + 'Candidates with Errors: ' + this.aggregator.aggWithError + '\n\n'
        + ((this.aggregator.errorLogbook.isEmpty()) ? 
            '' :
            'Database Error logbook:\n' + String.join(this.aggregator.errorLogbook, '\n\n')
          )
        + 'Callouts logbook:\n\n' + String.join(this.aggregator.callsLogbook, '\n');
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

        /*
        * Before setting up next attempt, check if we need to flush the PagingAggregator into a
        * partial result Developer_Log__c, to avoid runaway heap size in the Aggregator
        */
        manageAggregatorSize();

        //  Get the setup delay between attempts
        Integer delay = getDelayBetweenAttempts();

        //  If we've set up no delay and can still chain new jobs, enqueue one immediately
        if (delay <= 0 && this.depth < 5) {
            //  Only enqueue a new attempt if it's not a Test, as chaining is not allowed in tests
            if (!Test.isRunningTest()) {
                System.enqueueJob(new GetCandidatesPaged(
                    this.aggregator, this.startFrom, this.pageSize, this.attempt + 1, 
                    this.depth + 1, this.faulty, this.size
                    )
                );
            }
            return;
        }
        //  If we've set up no delay but are already at depth 5, instead break the chain
        if (delay <= 0) {
            breakChainAndRestart(
                this.aggregator, this.startFrom, this.pageSize, this.attempt + 1,this.faulty,
                this.size
            );
            return;
        }

        //  If there's some delay set up between attempts, schedule a new job to run in the future
        System.schedule(
            'GetCandidatesPaged attempt ' + this.attempt + 1 + ' ' + getCronInFuture(delay), 
            getCronInFuture(delay), 
            new GetCandidatesPagedScheduler(
                this.aggregator, this.startFrom, this.pageSize, this.attempt + 1, this.faulty,
                this.size
            )
        );
    }

    /*
    * Get the delay between attempts. This is usually set in the Custom Metadata Type, but we need
    * to be able to set it from a Test Class and retrieve that value to test both 0 and non-0 values
    */
    private Integer getDelayBetweenAttempts() {
        if (Test.isRunningTest()) {
            return TestUtils.testDelay;
        }

        return (Integer)Callout_Setting__mdt.getInstance('Heroku_Datasource')
                                            .Delay_Between_Attempts__c;
    }

    /*
    * Check if the number of received candidates is less than the page size. If so, then the last
    * page has been reached, and no more callouts should be made. Log that the job has finished.
    * If as many candidates were received as those requested, there may be more in future pages,
    * so immediately enqueue getting the next page if the stack depth is less than 5. If the stack
    * depth has reached 5, instead break the chain and schedule to continue it a bit in the future.
    */
    private void checkPaging(Integer receivedCandidates) {

        if (receivedCandidates == this.pageSize && this.depth < 5) {
            /*
            * If we're to enqueue a new page, first consider the PagingAggregator size, so as to
            * avoid runaway heap sizes
            */
            manageAggregatorSize();

            //  Only enqueue the job if we're not running tests, as chaining is not allowed in tests
            if (!Test.isRunningTest()) {
                System.enqueueJob(new GetCandidatesPaged(
                    this.aggregator, this.startFrom + this.pageSize, this.pageSize, 1, 
                    this.depth + 1, this.faulty, this.size
                    )
                );
            }
            return;
        }

        if (receivedCandidates == this.pageSize) {
            breakChainAndRestart(
                this.aggregator, this.startFrom + this.pageSize, this.pageSize, 1, this.faulty,
                this.size
            );
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
        Integer pageSize, Integer attempt, Boolean faulty, CandidatesCallout.Sizes size
    ) {
        /*
        * Before setting up the next link in the chain, consider the PagingAggregator size to avoid
        * runaway heap sizes
        */
        manageAggregatorSize();

        System.schedule(
            'GetCandidatesPaged attempt ' + attempt + ' ' + getCronInFuture(5), 
            getCronInFuture(5),
            new GetCandidatesPagedScheduler(
                aggregator, startFrom, pageSize, attempt, faulty, size
            )
        );
    }

    /*
    * Clean up any scheduled jobs that were created during previous failed callouts
    */
    private void cleanUpScheduledJobs(){
        /*
        * Get all scheduled job that have a name as those we set on this class for future
        * attempts, that have already ran once, and are not scheduled to run again, and abort them
        */
        for (CronTrigger job : [
                                SELECT Id
                                FROM CronTrigger
                                WHERE CronJobDetail.JobType = '7'
                                AND CronJobDetail.Name LIKE 'GetCandidatesPaged attempt%'
                                AND NextFireTime = NULL
                                AND TimesTriggered = 1
                                ]
        ) {
            System.abortJob(job.Id);
        }
    }

    /*
    * Manage the PagingAggregator estimated size so the aggregated information does not cause
    * heap size limits to be exceeded. Get a max allowed heap size from custom metadata type to be
    * alloted to the PagingAggregator. If the current Aggregator size surpasses this limit, flush
    * its results into a Developer_Log__c containing partial results, then reinstantiate the
    * Aggregator to a new one. Allow for the value to be set by the test context instead of the
    * custom metadata type so it can be properly tested.
    */
    private void manageAggregatorSize() {

        Double maxAggregatorSize = Callout_Setting__mdt.getInstance('Heroku_Datasource')
                                                       .Max_PagingAggregator_Heap_Size__c;
        if (Test.isRunningTest() && TestUtils.testMaxHeapSize != null) {
            maxAggregatorSize = TestUtils.testMaxHeapSize;
        }
        maxAggregatorSize = maxAggregatorSize / 100;

        if (this.aggregator.estHeapSize >= Limits.getLimitHeapSize() * maxAggregatorSize) {
            logPartialResult();
            this.aggregator = new PagingAggregator();
        }
    }
}