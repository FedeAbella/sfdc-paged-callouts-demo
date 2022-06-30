/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesBatch: Batchable class for upserting Candidates from Heroku endpoint via External ID
*
*   Batch Apex class for getting Candidates from a Heroku endpoint. The endpoint is defined by the
*       parameter size, which determines the amount of records the endpoint returns.
*       The callout that gets the records is made on the start method, and those are upserted using
*       the External_ID__c field in the execute method in batches. Class variables are used to keep
*       running totals and errors across batches, which are then informed in the finish method.
*
* Constructor:
*     - public GetCandidatesBatch(CandidatesCallout.Sizes size)
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.1
* @created        2022-06-25
* @modified       2022-06-25
* @systemLayer    Asynchronous/Batch/Callouts
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
*   2022-06-25 (v1.1): Minor changes to accomodate changes in CandidatesCallout
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class GetCandidatesBatch implements Database.Batchable<sObject>, Database.Stateful, 
    Database.AllowsCallouts
{

    //  INSTANCE VARIABLES
    /*
    * These are used for dynamically defining the correct endpoint to make the callout to.
    */
    private final CandidatesCallout.Sizes size; //  Callout size, used to define the final endpoint

    /*
    * These are used to keeping track of the job across all instances of the execute method.
    * That way we can, at the end of the entire job, create an informational log with accumulated
    * data.
    */
    private Integer received; //  Keeps track of total received candidate data
    private Integer withErrors; //  Keeps track of total candidates not-upserted (w/error)
    private Integer upserted; //  Keeps track of total upserted candidates
    private Integer inserted; //  Keeps track of total inserted candidates
    private Integer updated; //  Keeps track of total updated candidates
    private List<String> upsertErrors; //  Keeps a log of upsert errors found across all batches

    //  CONSTRUCTOR
    public GetCandidatesBatch(CandidatesCallout.Sizes size) {
        this.size = size;
        this.received = 0;
        this.withErrors = 0;
        this.upserted = 0;
        this.inserted = 0;
        this.updated = 0;
        this.upsertErrors = new List<String>();
    }

    public List<Candidate__c> start(Database.BatchableContext ctx) {
        /*
        * Attempt making a callout using the CandidatesCallout class, and save the results to
        * a list passed into the context. If any exceptions are raised during the callout, log
        * them into a Developer_Log__c record, and abort the entire job, as there's nothing to 
        * batch through
        */
        List<Candidate__c> candidateList = new List<Candidate__c>();
        try {
            candidateList = CandidatesCallout.getCandidates(this.size);
        } catch (Exception e) {
            DeveloperLogHandler.createDevLog(
                DeveloperLogHandler.LogType.ERROR,
                'GetCandidatesBatch Exception: ' + System.now(),
                'Exception Message: ' + e.getMessage() + '\n' 
                + 'Trace String: ' + e.getStackTraceString()
            );
            System.abortJob(ctx.getJobId());
        }

        return candidateList;
    }

    public void execute (Database.BatchableContext ctx, List<Candidate__c> candidatesBatch) {
        /*
        * This would be the place for some post-processing on the objects returned from the callout.
        * For simplicity's sake, in this demo we're just going to upsert those objects, but keep
        * track of received and upserted (created or updated) totals, as well as any errors found.
        */

        //  Update the total number of received candidates
        this.received += candidatesBatch.size(); 

        /*
        * Upsert the records using the External_ID__c field as identifier. Return any errors found,
        * but don't prevent those from upserting the correct ones
        */
        List<Database.UpsertResult> upsertResults = Database.upsert(
            candidatesBatch, Candidate__c.Fields.External_ID__c, false
        );

        /*
        * Go over the results of the upsert, update running totals and keep a log of records that
        * failed the upsert, as well as their errors for final logging
        */
        for (Database.UpsertResult result : upsertResults) {
            if (!result.isSuccess()) {
                this.withErrors += 1;
                String errorMessage = 'Errors during upsert: '
                    + JSON.serialize(
                        candidatesBatch.get(
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
                this.upsertErrors.add(errorMessage);
            } else {
                this.upserted += 1;
                if (result.isCreated()) {
                    this.inserted += 1;
                } else {
                    this.updated += 1;
                }
            }
        }
    }

    public void finish (Database.BatchableContext ctx) {

        /*
        * On finishing the entire job, insert a Developer_Log__c record of type INFO (or WARNING if
        * any errors were found during upsert), and add the running totals and error log to the
        * log message
        */
        DeveloperLogHandler.LogType logType = DeveloperLogHandler.LogType.INFO;
        String errorMessage = '';
        if (!this.upsertErrors.isEmpty()) {
            logType = DeveloperLogHandler.LogType.WARNING;
            errorMessage = 'Errors Found:\n' + String.join(this.upsertErrors, '\n\n');
        }

        DeveloperLogHandler.createDevLog(
            logType,
            'GetCandidatesBatch Finished: ' + System.now(), 
            'Received Candidates: ' + this.received + '\n'
            + 'Candidates with Errors: ' + this.withErrors + '\n'
            + 'Upserted Candidates: ' + this.upserted + '\n'
            + 'Inserted Candidates: ' + this.inserted + '\n'
            + 'Updated Candidates: ' + this.updated + '\n'
            + errorMessage
        );
        
    }
}