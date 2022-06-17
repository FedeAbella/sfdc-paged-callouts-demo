/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* CandidatesCallout: Get Candidates from an external Heroku Datasource
*
*   Class for making a callout to receive Candidate__c records from an external Heroku Datasource.
*   Callout is made using the getCandidates or getCandidatesPaged methods.
*
* Constructor: No constructor
*
* Methods:
*     - public static List<Candidate__c> getCandidates(
*           CandidatesCallout.Modes mode, CandidatesCallout.Sizes size) {}: Attempts a
*           callout to the Heroku_Datasource endpoint given by 'mode' and 'size', and returns a list
*           of Candidate__c objects from the response. Raises a CandidatesCalloutException if it
*           encounters some error.
*     - public static List<Candidate__c> getCandidatesPaged(Integer startFrom, Integer pageSize){}:
*           Makes a callout to the paged Heroku Datasource endpoint, with startFrom and pageSize
*           determining the range of data to request. Returns a list of Candidate__c objects built
*           from the response. Raises a CandidatesCalloutException if it encounters some error.
*     - private static makeCallout(String endpoint){}: Given the endpoint, makes the callout to
*           retrieve Candidate data, and returns a list of Candidate__c objects built from it.
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        2.0
* @created        2022-06-13
* @modified       2022-06-16
* @systemLayer    Callouts/REST
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
*   2022-06-16 (v2.0): Added the getCandidatesPaged method. 
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class CandidatesCallout {
    
    /*
    * Custom Exception for raising errors received as Exceptions, to be handled by calling class
    */
    public class CandidatesCalloutException extends Exception {}

    /*
    * Wrapper class for the response body. Allows for deserializing the JSON response into known
    * data types, avoiding the need for repeated casting
    */
    private class ResponseWrapper {
        public Boolean success;
        public String error;
        public List<Map<String,String>> data;
    }

    //  Allowed values for the 'mode' and 'size' parameters on the non-paged endpoints
    public Enum Modes {PARTIAL, RANDOM, COMPLETE}
    public Enum Sizes {SMALL, MEDIUM, LARGE}

    /*
    * Gets Candidate objects from a non-paged Heroku endpoint, using parameters 'mode' and 'size'
    * to define the correct endpoint to call
    */
    public static List<Candidate__c> getCandidates(Modes mode, Sizes size) {

        //  Verify required argument, and default size to small if not present
        if (mode == null) {
            throw new CandidatesCalloutException('mode is a required argument');
        }
        String modeArg = mode.name().toLowerCase();
        String sizeArg = (size == null) ? 'small' : size.name().toLowerCase();

        //  Get the base URL for the Callout
        String baseURL = Callout_Setting__mdt.getInstance('Heroku_Datasource').Base_URL__c;
        //  Complete the endpoint using the base URL + mode + size parameter if necessary
        String endpoint = baseURL //  Get the base URL
                        + modeArg //  Add the mode
                        + (
                            (modeArg == 'complete') ? '' : '?size=' + sizeArg
                        );
                        //  If mode is not complete, add the size parameter

        //  Make the callout and return the result
        return makeCallout(endpoint);
    }

    /*
    * Gets Candidate objects from a paged Heroku endpoint, using parameters startingElement and
    * pageSize to define which set of objects to retrieve
    */
    public static List<Candidate__c> getCandidatesPaged(Integer startFrom, Integer pageSize) {

        //  Define the start and end parameter values
        String startParam = String.valueOf(startFrom);
        String endParam = String.valueOf(startFrom + pageSize - 1);

        //  Get the base URL for the callout
        String baseURL = Callout_Setting__mdt.getInstance('Heroku_Datasource').Base_URL__c;
        //  Build the full endpoint using the base URL + paged endpoint + start + end parameters
        String endpoint = baseURL //  base URL
            + 'paged' //  paged endpoint
            + '?start=' + startParam //  start parameter
            + '&end=' + endParam; //  end parameter

        //  Make the callout and return the result
        return makeCallout(endpoint);
    }

    /*
    * Make the callout to the Heroku Datasource, given the right endpoint. The endpoint only
    * determines the set of data to return, so callouts are the same across paged and non-paged
    * methods, differing only on the endpoint used
    */
    private static List<Candidate__c> makeCallout(String endpoint) {
        //  Prepare the request
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(120000); //  Set a big timeout, needed for the larger sets of data

        HttpResponse response;
        try{
            response = http.send(request); //  Attempt the callout
        } catch (CalloutException e) {
            //  Raise a caught CalloutException as custom Exception, for handling by calling class
            throw new CandidatesCalloutException(e.getMessage());
        }

        //  Raise a custom Exception if we don't get a 200 code. Add response body to error message
        if (response.getStatusCode() != 200) {
            throw new CandidatesCalloutException(
                response.getStatusCode() + ': ' + response.getStatus() + ': ' + response.getBody()
            );
        }

        /*
        * If we get a 200 code, we can expect the response body to have the wrapper form
        * so we can deserialize into the wrapper class
        */
        ResponseWrapper responseWrp = (ResponseWrapper)JSON.deserialize(
            response.getBody(), ResponseWrapper.class
        );

        //  Raise a custom Exception if we don't successfully get data. Handled by calling class
        if (responseWrp.success != true) {
            throw new CandidatesCalloutException(
                responseWrp.error
            );
        }

        /*
        * If we get here, we got a successful response. Create the Candidate__c objects from the
        * data, and return the list
        */
        List<Candidate__c> candidateList = new List<Candidate__c>();
        for (Map<String,String> data : responseWrp.data) {
            candidateList.add(
                new Candidate__c(
                    Name = data.get('name'),
                    External_ID__c = data.get('id'),
                    Current_Position__c = data.get('job'),
                    Current_Company__c = data.get('company')
                )
            );
        }
        return candidateList;
    }
}