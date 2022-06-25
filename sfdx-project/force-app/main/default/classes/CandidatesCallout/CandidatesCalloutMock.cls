/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* CandidatesCalloutMock: Mock HTTP class for use in CandidatesCalloutTest. Mocks different callout
*       attempts to the Heroku endpoint which returns candidates.
*
* Constructors:
*     - public CandidatesCalloutMock (CandidatesCalloutMock.Errors error)
*     - public CandidatesCalloutMock (Integer numCandidates)
*     - public CandidatesCalloutMock (List<Candidate__c> candidateList)
*
* Methods:
*     - public HTTPResponse respond (HTTPRequest req): Responds to the callout, depending on the
*           parameters passed at construction. May throw a CalloutException, return a StatusCode
*           other than 200, return some error body, or a correct JSON containing Candidates data.
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-25
* @modified       2022-06-25
* @systemLayer    Mock/Test
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
@isTest
public class CandidatesCalloutMock implements HttpCalloutMock {

    private final Integer numCandidates; //  Number of candidates to return in correct callout
    private final List<Candidate__c> candidateList; // Fixed candidate list to return as response
    private final Errors error; //  Kind of error response we're looking for (see Error enum)

    /*
    * Enum used to define what kind of error we'd like in return, used in one of the constructors:
    * - CALLOUT: The callout throws a CalloutException
    * - CODE: The callout returns an HTTP error code, something other than 200
    * - DATA: The callout returns a 200 code, but the response body returns the pair 
    *       'success' => false and an error message
    */
    public Enum Errors {CALLOUT, CODE, DATA}

    /*
    * CONSTRUCTORS
    */
    public CandidatesCalloutMock(Errors error){
        this.error = error;
    }

    public CandidatesCalloutMock(Integer numCandidates) {
        this.numCandidates = numCandidates;
    }

    public CandidatesCalloutMock(List<Candidate__c> candidateList) {
        this.candidateList = candidateList;
    }

    /*
    * Respond to the callout depending on parameters passed
    */
    public HTTPResponse respond (HTTPRequest req) {

        //  Throw a CalloutException if required to in constructor
        if (this.error == Errors.CALLOUT) {
            throw new CalloutException('Some error happened');
        }

        //  Build the response headers
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');

        //  If the response is supposed to return some error code, return 400
        if (this.error == Errors.CODE) {
            res.setStatusCode(400);
            res.setStatus('BAD REQUEST');
            res.setBody('The request is invalid');
            return res;
        }

        /*
        * If the callout is successful but the response is not supposed to be a success,
        * return a JSON containing the pair 'success' => false and some error message
        */
        if (this.error == Errors.DATA) {
            res.setBody(
                TestUtils.generateCandidatesResponseFailureJSON()
            );
            res.setStatusCode(200);
            return res;
        }

        /* 
        * Otherwise, return 200 and a JSON containing Candidate data. If numCandidates was passed,
        * return that amount of random Candidate data. If a list was passed, return those as the
        * response
        */
        res.setBody(
            (this.numCandidates != null) ?
            TestUtils.generateRandomCandidateResponse(this.numCandidates) :
            TestUtils.generateCandidatesResponseJSON(this.candidateList)
        );
        res.setStatusCode(200);
        return res;
    }
}