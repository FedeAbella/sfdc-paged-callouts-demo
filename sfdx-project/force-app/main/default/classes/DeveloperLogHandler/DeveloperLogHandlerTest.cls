/*
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* DeveloperLogHandlerTest: Test class for testing the DeveloperLogHandler class
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
private class DeveloperLogHandlerTest {
    
    /*
    * Test creating an error log using the DeveloperLogHandler class
    */
    @IsTest
    static void testCreateLog(){
        
        Test.startTest();
            DeveloperLogHandler.createDevLog(
                DeveloperLogHandler.LogType.ERROR, 
                'Test Log', 
                'Some error happened and this is a log for it'
            );
        Test.stopTest();

        List<Developer_Log__c> logsList = [
            SELECT Name, Type__c, Message__c
            FROM Developer_Log__c
        ];

        System.assertEquals(1, logsList.size());
        System.assertEquals('ERROR', logsList[0].Type__c);
        System.assertEquals('Test Log', logsList[0].Name);
        System.assertEquals(
            'Some error happened and this is a log for it', 
            logsList[0].Message__c
        );
    }

    @IsTest
    static void testCreateSplitLog(){
        
        Integer fieldSize = Developer_Log__c.Message__c.getDescribe().getLength();

        Test.startTest();
            DeveloperLogHandler.createDevLog(
                DeveloperLogHandler.LogType.INFO, 
                'Split log test', 
                'a'.repeat(fieldsize + 1)
            );
        Test.stopTest();

        List<Developer_Log__c> logsList = [
            SELECT Type__c, Name, Message__c
            FROM Developer_Log__c
            ORDER BY Name ASC
        ];

        System.assertEquals(2, logsList.size());
        System.assert(
            logsList[0].Name.contains('(1/2)')
        );
        System.assert(
            logsList[1].Name.contains('(2/2)')
        );
    }
}
