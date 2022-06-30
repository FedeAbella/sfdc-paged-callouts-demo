/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* DeveloperLogHandler: Handler for working with Developer_Log__c records
*
*   Handler class to outsource logic having to do with logging information or errors into
*   Developer_Log__c records, and keep calling classes simplified.
*
* Constructor: No constructor
*
* Methods:
*     - public static void createDevLog(
*           DeveloperLogHandler.LogType type, String name, String message
*       )
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Federico Abella   <federico.abella@cloudgaia.com>
* @modifiedBy     Federico Abella   <federico.abella@cloudgaia.com>
* @maintainedBy   Federico Abella   <federico.abella@cloudgaia.com>
* @version        1.0
* @created        2022-06-14
* @modified       2022-06-14
* @systemLayer    Utility
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @changes
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public class DeveloperLogHandler {
    
    public Enum LogType {INFO, WARNING, ERROR}

    public static void createDevLog(LogType type, String name, String message){
        
        /*
        * Check if the message string is possibly too long to fit into the field. This can happen
        * when writing records from very long paged callouts with many callout or upsert errors.
        * If this happens, split the log up into parts, and insert multiple parts.
        */
        if (message.length() >= Developer_Log__c.Message__c.getDescribe().getLength()) {
            splitUpLog(type, name, message);
            return;
        }

        insert new Developer_Log__c(
            Name = name,
            Type__c = type.name(),
            Message__c = message
        );
    }
    private static void splitUpLog(LogType type, String name, String message) {
        /*
        * Get how many parts we need to split the message up. Assume we'll only use 90% of the total
        * available size on each part (we'll leave some room for truncated message info)
        */
        Integer partLength = (Integer)Math.floor(
            Developer_Log__c.Message__c.getDescribe().getLength() * 0.9
        );
        Integer partsNeeded = (Integer)Math.ceil(
            (Double)message.length() / partLength
        );

        List<Developer_Log__c> logsList = new List<Developer_Log__c>();
        for (Integer i = 0; i < partsNeeded; i++){
            /*
            * Create one log using the first partLength substring of the total message, and add 
            * some additional information regarding truncation and parts count
            */
            Developer_Log__c part = new Developer_Log__c(
                Type__c = type.name(),
                Name = name + ' (' + String.valueOf(i + 1) + '/' + partsNeeded + ')'
            );

            if (i < partsNeeded - 1) {
                part.Message__c = message.substring(0, partLength) + '\n(message truncated...)';
                message = message.substring(partLength);
            } else {
                part.Message__c += message + '\n(end of truncated message)';
            }

            logsList.add(part);
        }
        insert logsList;
    }
}