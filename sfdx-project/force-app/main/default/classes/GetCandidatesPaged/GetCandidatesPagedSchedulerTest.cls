/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* GetCandidatesPagedSchedulerTest: Test class for the GetCandidatesPagedScheduled class
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
private class GetCandidatesPagedSchedulerTest {
    
    //  Test scheduling a new job for the GetCandidatesPaged Queueable class
    @IsTest
    static void testScheduleNewJob(){
        
        Test.startTest();
            TestUtils.testDelay = 10;
            Test.setMock(
                HttpCalloutMock.class, 
                new CandidatesCalloutMock(
                    CandidatesCalloutMock.Errors.CALLOUT
                )
            );
            GetCandidatesPagedScheduler scheduledJob = new GetCandidatesPagedScheduler(
                new GetCandidatesPaged.PagingAggregator(), 1, 500, 1, false, 
                CandidatesCallout.Sizes.COMPLETE
            );

            String cron = '0 0 0 * * ? *';
            System.schedule('GetCandidatesPagedSchedulerTest', cron, scheduledJob);
        Test.stopTest();

        List<AsyncApexJob> jobList = [
            SELECT ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];

        //  Assert our scheduled job has put the job in the queue
        System.assertEquals(1, jobList.size());
        System.assertEquals('GetCandidatesPaged', jobList[0].ApexClass.Name);
        System.assertEquals('Queued', jobList[0].Status);
    }
}
