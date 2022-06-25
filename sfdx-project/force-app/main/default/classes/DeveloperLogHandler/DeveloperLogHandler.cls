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
        insert new Developer_Log__c(
            Name = name,
            Type__c = type.name(),
            Message__c = message
        );
    }
}