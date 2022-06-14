/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* CandidatesCallout: Get Candidates from an external Heroku Datasource
*
*   Class for making a callout to receive Candidate__c records from an external Heroku Datasource.
*   Callout is made using the getCandidates method.
*
* Constructor: No constructor
*
* Methods:
*     - private static List<Candidate__c> getCandidates(String mode, String size): Attempts a
*           callout to the Heroku_Datasource endpoint given by 'mode' and 'size', and returns a list
*           of Candidate__c objects from the response. Raises a CandidatesCalloutException if it
*           encounters some error.
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-13
* @modified       2022-06-13
* @systemLayer    Callouts/REST
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
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

    //  Allowed values for the 'mode' and 'size' parameters
    private static Set<String> MODES = new Set<String>{'partial','random','complete'};
    private static Set<String> SIZES = new Set<String>{'small','medium','large'};

    public static List<Candidate__c> getCandidates(String mode, String size) {

        //  Check for validity of parameters. 'size' is also allowed to be blank.
        if (!MODES.contains(mode) ||
            (
                String.isNotBlank(size) &&
                !SIZES.contains(size)
            )
        ){
            throw new CandidatesCalloutException('mode or size is invalid');
        }

        //  Get the Heroku_Datasource base URL
        NamedCredential credential = [
            SELECT Endpoint
            FROM NamedCredential
            WHERE DeveloperName = 'Heroku_Datasource'
        ];

        //  Complete the endpoint using the base URL + mode + size parameter if necessary
        String endpoint = credential.Endpoint //  Get the base URL
                        + mode //  Add the mode
                        + (
                            mode == 'complete' ? '' : ( //  If mode is complete, don't add parameter
                                String.isBlank(size) ? '?size=small' : ('?size=' + size)
                                //  Otherwise, add size parameter, or default to small
                            )
                        );

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
