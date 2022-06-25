/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* TestUtils: Utility class with a collection of methods to be used in Test classes and Mocks
*
*
* Methods:
*     - public static String generateCandidatesResponseFailureJSON(): Returns a JSON like the one
*           the Heroku endpoint would return if it encountered some error
*     - public static String generateRandomCandidateResponse(Integer numCandidates): Returns a
*           response with a set number of random candidate data in JSON form
*     - public static String generateCandidatesResponseJSON(List<Candidate__c> candidateList): 
*           Given a list of Candidate__c objects, generates a JSON that replicates the one that 
*           would be returned from the Heroku endpoint.
*     - public static List<Candidate__c> makeCandidates(Integer numCandidates): Generates a list of
*           numCandidates random Candidate__c objects.
*     - public static String generateRandomCandidateID(): Generates a random External_Id__c for a 
*           Candidate__c object, following the format used by the Heroku endpoint.
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
public class TestUtils {

    public static String generateCandidatesResponseFailureJSON() {
        Map<String,Object> responseMap = new Map<String,Object>();
        responseMap.put('success', false);
        responseMap.put('error', 'Some error happened');
        return JSON.serialize(responseMap);
    }

    public static String generateRandomCandidateResponse(Integer numCandidates) {
        List<Candidate__c> candidateList = makeCandidates(numCandidates);
        return generateCandidatesResponseJSON(candidateList);
    }

    public static String generateCandidatesResponseJSON(List<Candidate__c> candidateList) {
        Map<String,Object> responseMap = new Map<String,Object>();
        List<Map<String,String>> dataList = new List<Map<String,String>>();
        for (Candidate__c c : candidateList) {
            dataList.add(
                new Map<String,String>{
                    'name' => c.Name,
                    'job' => c.Current_Position__c,
                    'company' => c.Current_Company__c,
                    'id' => c.External_ID__c
                }
            );
        }
        responseMap.put('data', dataList);
        responseMap.put('success', true);
        return JSON.serialize(responseMap);
    }

    public static List<Candidate__c> makeCandidates(Integer numCandidates) {
        List<Candidate__c> candidatesList = new List<Candidate__c>();
        for (Integer count = 0; count < numCandidates; count++) {
            candidatesList.add(
                new Candidate__c(
                    Name = 'Test Candidate ' + count,
                    Current_Position__c = 'Sr. Tester',
                    Current_Company__c = 'Test & Co. LTD',
                    External_ID__c = generateRandomCandidateID()
                )
            );
        }

        return candidatesList;
    }

    public static String generateRandomCandidateID() {
        String randomID = String.fromCharArray(
            new List<Integer>{ 
                (Integer)Math.round(Math.random() * 25 + 65), 
                (Integer)Math.round(Math.random() * 25 + 65),
                (Integer)Math.round(Math.random() * 25 + 65)
            }
        )
        + String.valueOf(
            (Integer)Math.round(Math.random() * 1000000)
        ).leftPad(10,'0');

        return randomID;
    }
}
