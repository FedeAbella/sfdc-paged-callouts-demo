/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* CandidatesCalloutTest: Test class for the CandidatesCallout class.
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
private class CandidatesCalloutTest {
    
    /*
    * Test a correct callout to the non-paged endpoint that returns a set of Candidate data
    */
    @IsTest
    static void testNonPagedOK(){

        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(500)
        );
        
        List<Candidate__c> candidatesList = CandidatesCallout.getCandidates(
            CandidatesCallout.Sizes.COMPLETE
        );

        System.assertEquals(500, candidatesList.size());
    }

    /*
    * Test a callout to the non-paged endpoint that returns some error code as part of the response
    */
    @IsTest
    static void testNonPagedErrorCode(){
        
        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CODE)
        );

        CandidatesCallout.CandidatesCalloutException calloutException;

        try {
            List<Candidate__c> candidatesList = CandidatesCallout.getCandidates(
                CandidatesCallout.Sizes.COMPLETE
            );
        } catch (CandidatesCallout.CandidatesCalloutException e) {
            calloutException = e;
        }

        System.assertNotEquals(null, calloutException);
        System.assertEquals(
            '400: BAD REQUEST: The request is invalid', 
            calloutException.getMessage()
        );
    }

    /*
    * Test a callout to the non-paged endpoint that returns a 200 code, but the response contains
    * an error and the pair 'success' => false
    */
    @IsTest
    static void testNonPagedError(){

        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(CandidatesCalloutMock.Errors.DATA)
        );
        
        CandidatesCallout.CandidatesCalloutException calloutException;

        try {
            List<Candidate__c> candidatesList = CandidatesCallout.getCandidates(
                CandidatesCallout.Sizes.COMPLETE
            );
        } catch (CandidatesCallout.CandidatesCalloutException e) {
            calloutException = e;
        }

        System.assertNotEquals(null, calloutException);
        System.assertEquals(
            'Some error happened', 
            calloutException.getMessage()
        );
    }

    /*
    * Test a callout to the non-paged endpoint that throws a Callout Exception
    */
    @IsTest
    static void testNonPagedException(){
        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(CandidatesCalloutMock.Errors.CALLOUT)
        );

        CandidatesCallout.CandidatesCalloutException calloutException;

        try {
            List<Candidate__c> candidatesList = CandidatesCallout.getCandidates(
                CandidatesCallout.Sizes.COMPLETE
            );
        } catch (CandidatesCallout.CandidatesCalloutException e) {
            calloutException = e;
        }

        System.assertNotEquals(null, calloutException);
        System.assertEquals('Some error happened', calloutException.getMessage());
    }

    /*
    * Test a callout to the paged endpoint that returns a correct set of Candidate data
    */
    @IsTest
    static void testPagedOK(){
        
        Test.setMock(
            HttpCalloutMock.class, 
            new CandidatesCalloutMock(500)
        );

        List<Candidate__c> candidatesList = CandidatesCallout.getCandidatesPaged(
            1, 500, false, CandidatesCallout.Sizes.COMPLETE
        );

        System.assertEquals(500, candidatesList.size());
    }

    /*
    * No need to re-test error codes, callout exceptions or errors in returned data using the paged
    * method, since we know those are handled by CandidatesCallout.makeCallout() and have been
    * tested in previous test methods.
    */
}
