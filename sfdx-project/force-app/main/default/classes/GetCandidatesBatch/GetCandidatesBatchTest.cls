/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesBatchTest: Test class for testing the GetCandidatesBatch Apex class
*
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-25
* @modified       2022-06-25
* @systemLayer    Test
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
@isTest
private class GetCandidatesBatchTest {

    /*
    * Test a Batch job that fails on the start method because of a CalloutException
    */
    @isTest
    static void testFailedCallout() {
        
        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CALLOUT)
        );

        Test.startTest();
            GetCandidatesBatch batchJob = new GetCandidatesBatch(CandidatesCallout.Sizes.COMPLETE);
            Database.executeBatch(batchJob, 500);
        Test.stopTest();

        //  Assert the correct Developer_Log__c record was inserted as part of the callout failing
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];

        System.assertEquals(1, logsList.size());
        System.assertEquals('ERROR', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith('GetCandidatesBatch Exception:')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'Exception Message: Some error happened'
            )
        );
    }

    /*
    * Test a Batch Job that correctly inserts 2000 new records
    */
    @IsTest
    static void testCorrectBatchInsert(){

        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(2000)
        );
        
        Test.startTest();
            GetCandidatesBatch batchJob = new GetCandidatesBatch(CandidatesCallout.Sizes.COMPLETE);
            Database.executeBatch(batchJob, 2000);
        Test.stopTest();

        //  Assert the correct number of Candidate__c records were inserted
        Integer candidateCount = [
            SELECT COUNT()
            FROM Candidate__c
        ];
        System.assertEquals(2000, candidateCount);

        //  Assert the correct Developer_Log__c record was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        
        System.assertEquals(1, logsList.size());
        System.assertEquals('INFO', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith(
                'GetCandidatesBatch Finished:'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Received Candidates: 2000'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Candidates with Errors: 0'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Upserted Candidates: 2000'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Inserted Candidates: 2000'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Updated Candidates: 0'
            )
        );
    }

    /*
    * Test a Batch job that upserts 2000 records that already exist in the database
    */
    @IsTest
    static void testCorrectBatchUpdate(){
        
        //  Get some random candidates an insert them
        List<Candidate__c> candidateList = TestUtils.makeCandidates(2000);
        insert candidateList;

        //  Modify only half of them, changing the name
        for (Candidate__c c : candidateList) {
            if (Math.mod(candidateList.indexOf(c), 2) == 0) {
                c.Name += ' Modified';
            }
        }

        //  Pass the entire list (modified and non-modified) to the Mock class to be returned later
        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(candidateList)
        );

        Test.startTest();
            GetCandidatesBatch batchJob = new GetCandidatesBatch(CandidatesCallout.Sizes.COMPLETE);
            Database.executeBatch(batchJob, 2000);
        Test.stopTest();
        
        //  Assert we still have the same number of Candidate__c records as before
        Integer candidateCount = [
            SELECT COUNT()
            FROM Candidate__c
        ];
        System.assertEquals(2000, candidateCount);

        //  Assert the correct Developer_Log__c record was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        
        System.assertEquals(1, logsList.size());
        System.assertEquals('INFO', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith(
                'GetCandidatesBatch Finished:'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Received Candidates: 2000'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Candidates with Errors: 0'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Upserted Candidates: 2000'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Inserted Candidates: 0'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Updated Candidates: 2000'
            )
        );
    }

    /*
    * Test a batch job that upserts all but 1 of the records in the database, but encounters
    * an error on one of the records
    */
    @IsTest
    static void testUpsertWithErrors(){

        //  Get some random candidates an insert them
        List<Candidate__c> candidateList = TestUtils.makeCandidates(2000);
        insert candidateList;

        //  Modify the first one, making the External_ID__c field too long
        candidateList[0].External_ID__c = '0'.repeat(20);

        //  Pass the entire list (modified and non-modified) to the Mock class to be returned later
        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(candidateList)
        );

        Test.startTest();
            GetCandidatesBatch batchJob = new GetCandidatesBatch(CandidatesCallout.Sizes.COMPLETE);
            Database.executeBatch(batchJob, 2000);
        Test.stopTest();
        
        //  Assert we still have the same number of Candidate__c records as before
        Integer candidateCount = [
            SELECT COUNT()
            FROM Candidate__c
        ];
        System.assertEquals(2000, candidateCount);

        //  Assert the correct Developer_Log__c record was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        
        System.assertEquals(1, logsList.size());
        System.assertEquals('WARNING', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith(
                'GetCandidatesBatch Finished:'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Received Candidates: 2000'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Candidates with Errors: 1'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Upserted Candidates: 1999'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Inserted Candidates: 0'
            )
        );
        System.assert(
            logsList[0].Message__c.contains(
                'Updated Candidates: 1999'
            )
        );
    }
}