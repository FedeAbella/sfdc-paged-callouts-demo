/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesPagedTest: Test class for the GetCandidatesPaged Queueable class
*
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-26
* @modified       2022-06-26
* @systemLayer    Test
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
@isTest
private class GetCandidatesPagedTest {
    
    //  Test handling an attempt made that goes beyond the maximum allowed number of attempts
    @IsTest
    static void testAttemptBeyondMaxAllowed(){
        
        Integer maxAttempts = (Integer)Callout_Setting__mdt.getInstance('Heroku_Datasource')
                                                           .Max_Paged_Attempts__c;
        Test.startTest();
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, maxAttempts + 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        //  Assert the correct Developer_Log__c was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        System.assertEquals(1, logsList.size());
        System.assertEquals('ERROR', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.contains('Exception')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'GetCandidatesPaged class exceeded maximum number of allowed attempts'
            )
        );
    }

    /* 
    * Test handling the callout returning an exception when we've still got attempts left, and the
    * delay between attempts is set to greater than 0. All exceptions are handled the same, so 
    * it's enough to test handling one of the possible types of exceptions
    */
    @IsTest
    static void testCalloutExceptionAttemptsLeftAndDelay(){
        
        Test.startTest();
            //  Set the delay to be greater than 0. This ensure the new attempt is scheduled
            TestUtils.testDelay = 30;

            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CALLOUT)
            );
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        /*
        *  Assert the job has run and completed, and a new one was put into the queue by the
        * scheduler
        */
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY Status
        ];
        System.assertEquals(2, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Queued', jobsList[0].Status);
        System.assertEquals('GetCandidatesPaged', jobsList[1].ApexClass.Name);
        System.assertEquals('Completed', jobsList[1].Status);
    }

    @IsTest
    static void testCalloutExceptionAttemptsLeftAndNoDelay(){
        
        Test.startTest();
            //  Set the delay to be 0. This calls for the next attempt to be enqueued immediately
            TestUtils.testDelay = 0;

            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CALLOUT)
            );
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        /*
        * Assert the job has run and completed, but no new one was put in the queue (we're not
        * allowed to chain queueable jobs in Test classes and this is handled by the class)
        */
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY Status
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);
    }

    /*
    * Test the callout receiving and exception, and having to break up the queueable chain
    * because the max depth has been reached
    */
    @IsTest
    static void testCalloutExceptionAndMaxDepth(){
        
        Test.startTest();
            //  Set the delay to be 0. This calls for the next attempt to be enqueued immediately
            TestUtils.testDelay = 0;

            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CALLOUT)
            );
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 5, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();

        /*
        *  Assert the job has run and completed, and a new one was put into the queue by the
        * scheduler
        */
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY Status
        ];
        System.assertEquals(2, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Queued', jobsList[0].Status);
        System.assertEquals('GetCandidatesPaged', jobsList[1].ApexClass.Name);
        System.assertEquals('Completed', jobsList[1].Status);
    }

    /*
    * Test the callout receiving an exception, and having no more attempts left
    */
    @IsTest
    static void testCalloutExceptionAndMaxAttemptsReached(){

        Integer maxAttempts = (Integer)Callout_Setting__mdt.getInstance('Heroku_Datasource')
                                                           .Max_Paged_Attempts__c;
        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CALLOUT)
            );

            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, maxAttempts, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        //  Assert the correct Developer_Log__c was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        System.assertEquals(1, logsList.size());
        System.assertEquals('ERROR', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.contains('Max Attempts Reached')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'GetCandidatesPaged class has reached the maximum number of allowed attempts'
            )
        );
    }

    /*
    * Test the callout working correctly but receiving no data (going beyond last page)
    */
    @IsTest
    static void testCorrectCalloutNoDataReturned(){
        
        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(0)
            );

            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        //  Assert the correct Developer_Log__c was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        System.assertEquals(1, logsList.size());
        System.assertEquals('INFO', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith('Get Candidates Paged Complete')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'GetCandidatesPaged class has completed the job'
            )
        );
    }

    /*
    * Test the callout receiving a full page of data correctly, and all is inserted. Depth is less
    * than maximum.
    */
    @IsTest
    static void testCorrectCalloutFullPageInsert(){
        
        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(100)
            );

            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();

        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        Integer numCandidates = [
            SELECT COUNT()
            FROM Candidate__c
        ];

        System.assertEquals(100, numCandidates);

        /*
        * We can't assert for Aggregator messages here, since the job didn't technically finish, 
        * we're just not allowed to chain the next page in tests
        */
    }

    /*
    * Test the callout receiving a full page of data correctly, and all is inserted. We've also
    * reached the maximum depth, so the next paged is scheduled instead of enqueued.
    */
    @IsTest
    static void testCorrectCalloutFullPageInsertMaxDepth(){
        
        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(100)
            );

            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 5, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();

        //  Assert the job has run and completed, and the next page has been enqueued by scheduler
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY Status
        ];
        System.assertEquals(2, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Queued', jobsList[0].Status);
        System.assertEquals('GetCandidatesPaged', jobsList[1].ApexClass.Name);
        System.assertEquals('Completed', jobsList[1].Status);

        //  Assert the received candidates were inserted
        Integer numCandidates = [
            SELECT COUNT()
            FROM Candidate__c
        ];

        System.assertEquals(100, numCandidates);

        /*
        * We can't assert for Aggregator messages here, since the job didn't technically finish, 
        * it's just been cut short by the next page.
        */
    }

    /*
    * Test the callout receiving data correctly, but less than the amount requested for, indicating
    * we've reached the last page
    */
    @IsTest
    static void testCorrectCalloutNonCompletePageInsert(){
        
        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(20)
            );
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        //  Assert the entire received candidates were inserted
        Integer numCandidates = [
            SELECT COUNT()
            FROM Candidate__c
        ];
        System.assertEquals(20, numCandidates);

        //  Assert the correct Developer_Log__c record was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        System.assertEquals(1, logsList.size());
        System.assertEquals('INFO', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith('Get Candidates Paged Complete')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'GetCandidatesPaged class has completed the job'
            )
        );
        System.assert(
            logsList[0].Message__c.contains('Received Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Upserted Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Inserted Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Updated Candidates: 0')
        );
        System.assert(
            logsList[0].Message__c.contains('Candidates with Errors: 0')
        );
    }

    /*
    * Test the callout receiving data correctly, but less than the amount requested for, indicating
    * we've reached the last page. However, the Candidates are matched by External_ID__c and updated
    * instead of being inserted
    */
    @IsTest
    static void testCorrectCalloutNonCompletePageUpdate(){
        
        //  Insert 100 Candidates, and modify the name of 20 of them to pass to Mock class
        List<Candidate__c> candidates = TestUtils.makeCandidates(100);
        insert candidates;

        List<Candidate__c> modifiedCandidates = new List<Candidate__c>();
        for (Integer count = 0; count < 20; count++) {
            Candidate__c c = candidates.get(count);
            c.Name += ' Modified';
            modifiedCandidates.add(c);
        }

        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(modifiedCandidates)
            );
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        //  Assert the number of candidates in database has not changed
        Integer numCandidates = [
            SELECT COUNT()
            FROM Candidate__c
        ];
        System.assertEquals(100, numCandidates);

        //  Assert the correct number of candidates were modified in database
        Integer numModifiedCandidates = [
            SELECT COUNT()
            FROM Candidate__c
            WHERE Name LIKE '%Modified'
        ];
        System.assertEquals(20, numModifiedCandidates);

        //  Assert the correct Developer_Log__c record was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        System.assertEquals(1, logsList.size());
        System.assertEquals('INFO', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith('Get Candidates Paged Complete')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'GetCandidatesPaged class has completed the job'
            )
        );
        System.assert(
            logsList[0].Message__c.contains('Received Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Upserted Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Inserted Candidates: 0')
        );
        System.assert(
            logsList[0].Message__c.contains('Updated Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Candidates with Errors: 0')
        );
    }

    /*
    * Test the callout receiving data correctly, but less than the amount requested for, indicating
    * we've reached the last page. However, one of the received Candidate__c objects fails to upsert
    * because the External_ID__c does not match field requirements
    */
    @IsTest
    static void testCorrectCalloutNonCompletePageUpdateWithError(){
        
        //  Insert 100 Candidates, and modify the name of 20 of them to pass to Mock class
        List<Candidate__c> candidates = TestUtils.makeCandidates(100);
        insert candidates;

        List<Candidate__c> modifiedCandidates = new List<Candidate__c>();
        for (Integer count = 0; count < 20; count++) {
            Candidate__c c = candidates.get(count);
            c.Name += ' Modified';
            modifiedCandidates.add(c);
        }

        //  Modify the External_ID__c of the first Candidate to be incompatible with our field
        modifiedCandidates[0].External_ID__c = '0'.repeat(20);

        Test.startTest();
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(modifiedCandidates)
            );
            GetCandidatesPaged queueableJob = new GetCandidatesPaged(
                new GetCandidatesPaged.PagingAggregator(), 1, 100, 1, 1, false,
                CandidatesCallout.Sizes.COMPLETE
            );
            System.enqueueJob(queueableJob);
        Test.stopTest();
        
        //  Assert the job has run and completed
        List<AsyncApexJob> jobsList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];
        System.assertEquals(1, jobsList.size());
        System.assertEquals('GetCandidatesPaged', jobsList[0].ApexClass.Name);
        System.assertEquals('Completed', jobsList[0].Status);

        //  Assert the number of candidates in database has not changed
        Integer numCandidates = [
            SELECT COUNT()
            FROM Candidate__c
        ];
        System.assertEquals(100, numCandidates);

        //  Assert the correct number of candidates were modified in database
        Integer numModifiedCandidates = [
            SELECT COUNT()
            FROM Candidate__c
            WHERE Name LIKE '%Modified'
        ];
        System.assertEquals(19, numModifiedCandidates);

        //  Assert the correct Developer_Log__c record was created
        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];
        System.assertEquals(1, logsList.size());
        System.assertEquals('WARNING', logsList[0].Type__c);
        System.assert(
            logsList[0].Name.startsWith('Get Candidates Paged Complete')
        );
        System.assert(
            logsList[0].Message__c.startsWith(
                'GetCandidatesPaged class has completed the job'
            )
        );
        System.assert(
            logsList[0].Message__c.contains('Received Candidates: 20')
        );
        System.assert(
            logsList[0].Message__c.contains('Upserted Candidates: 19')
        );
        System.assert(
            logsList[0].Message__c.contains('Inserted Candidates: 0')
        );
        System.assert(
            logsList[0].Message__c.contains('Updated Candidates: 19')
        );
        System.assert(
            logsList[0].Message__c.contains('Candidates with Errors: 1')
        );
        System.assert(
            logsList[0].Message__c.contains('External_ID__c')
        );
    }
}
