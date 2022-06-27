# The actual SFDX project

Ok, this is probably what you're here for, so let's go over it. This is just an `sfdx` project, same as if you created it using `sfdx-cli` or VSCode. Feel free to push this into a fresh new org to see how it works (some disclaimers at the bottom of this apply, so keep on reading).

TL;DR: If you don't really care about the whole structure of the thing and want to get right into the action, jump ahead to [this section](#ok,-that's-good-and-all,-but-i-want-to-try-it-out-for-myself-now.-how-do-i-do-that?) 

## The metadata

### Custom Objects

- The `Candidate__c` object is where we're holding our Candidate records. It has the fields:
	- `Name`, the standard record Name field, used for holding the Candidate's full name
	- `Current_Company__c` holds the respective `company` field from the csv
	- `Current_Position__c` same as above, but for the `position` field in the csv
	- `External_ID__c` same, but for the `id` field in the csv. This is truncated to 13 chars, which is important for testing failed upserts
- The `Developer_Log__c` object is used for writing logs into the org about how our asynchronous jobs went, help in debugging or identifying potential issues. For this demo's purposes, `Developer_Log__c` records will be used to inform admins as to whether the jobs failed, or completed successfully, along with some important information about the job. I personally believe having an object like this in big projects brings a lot more visibility to devs and admins over complex processes, and just makes everyone's lives a lot easier. It uses fields:
	- `Name`, the standard field
	- `Type__c`, a picklist with values `INFO`, `WARNING`, or `ERROR`
	- `Message__c`, a long area text for holding any details pertaining to the job that created the log

Objects come with their Tabs, layouts, and List Views, no need to detail on those.

### Other setup relevant metadata

- A custom App `Candidate Management` for easier access to the `Candidate` and `Developer Log` tabs
- Remote Site Settings for accessing the endpoint
- An `Admins` Public Group, an Email Template and Email Alert, along with a Flow, so all admins in the Group are notified via Email whenever a `Developer_Log__c` record is created, with the email containing info on the record.
- A Custom Metadata Type, `Callout_Setting__mdt` which holds:
	- The base URL for the Heroku app
	- The maximum number of allowed re-tries on failed callouts, before we give up
	- A delay in seconds to wait before re-trying after a failed callout. See more about this in the `GetCandidatesPaged` class

### The Apex Classes

- `DeveloperLogHandler` simply outsources creating a new `Developer_Log__c` record, since we're doing a lot of that to keep our Admins informed on how processes went, so it's useful to keep it handy in a single method. Also helps with readability in other classes. The class has an Enum to enforce the `Type__c` picklist values.
- `TestUtils` just has some useful methos for creating or transforming data for use in tests. It's always handy to keep one of this around.

Ok, now onto the important ones:
- `CandidatesCallout` is the class making the actual callout to the endpoint and receiving the Candidate data. It contains methods for calling either the non-paged or the paged endpoints, as those take different parameters. Calling the faulty endpoint is done as part of calling the paged one. If it receives some Candidate data, it will transform it into actual `Candidate__c` objects, and return a `List<Candidate__c>`. If it finds any errors, it will re-raise them as a Custom `CandidatesCalloutException`. This includes: Callout Exceptions, HTTP codes other than `200`, or if the response returns an error message. An Enum enforces the values of the `size` URL parameter.
- `GetCandidatesBatch` represents the pre-existing solution for getting updates from the external system, as it was before we re-wrote it to deal with the errors caused by the large amount of data. It makes the callout to the non-paged endpoint during the `start` method, and then processes the result in chunks during `execute`. Processing the Candidates is just Upserting them, as we don't need to simulate any complex logic here. A set of instance variables are used for keeping track of totals along batches, as well as holding any errors found during upsert. This data is all used in `finish` to write a detailed `Developer_Log__c` with the job results.

`GetCandidatesPaged` represents our re-work into getting the data in a paged manner, while also handling possible failed callouts by re-trying them. Since this is the main course of this demo, it's worth detailing it a bit further:

#### The Paging Aggregator
This is an inner class that works the same as the instance variables in the `GetCandidatesBatch` do. It's entire purpose is to aggregate data as we move through different pages, keeping track of totals, database errors, and callout results. Since every new Queueable class in the chain is an entire new instance, instance variables as used in `GetCandidatesBatch` just won't cut it. However, passing around the same instance of the `PagingAggregator` allows links in the chain to pass information to those coming after them. I like to think of it as runners in a relay race, passing forward the baton. If that also works for you, awesome!

#### Attempting a Callout
The class uses `CandidatesCallout` to attempt the callout and receive a list of Candidate data. This can either:
- Be a successful callout: In this case, we process the received Candidates (upserting them, in this demo), and move on to the next page.
- Fail in making the callout, either because a `CalloutException` was thrown, or some error was found in `CandidatesCallout` which was re-raised as a `CandidatesCalloutException`. In this case, we're making a new attempt at the same page, if we've still got some attempts left, as dictated by the `Callout_Setting__mdt` Custom Metadata Type. If we've got no more attempts left, we'll just create a `Developer_Log__c` record detailing this, whatever data the Paging Aggregator has gathered so far, and quit the entire job.

#### New Pages and New Attempts
Both calling for the next page after a successful callout, or re-trying a failed one work in the same way. We're making use of the fact that Queueable Apex classes can be 'chained': This means that we can enqueue a new Queueable job *from inside a Queueable job*. Nifty, huh? This also means we can enqueue a new instance of the same class we're in. Of course, this is a fresh new instance, within a fresh transaction, with fresh governor limits. This is why we're using the Paging Aggregator to communicate between links in the chain.

So, if we're successful and need to call the next page, we'll just enqueue a new instance of our same class, simply changing the parameters than tell the api which chunk (page) of data we want. Simple enough. And if our callout failed, we'll just enqueue a new instance, indicating the same page parameters, but increasing the attempt number by 1.

#### Wait, that's it? So what's that Schedulable class doing there then?
Ahh, you're an observant one. I mean, that's pretty much it, yeah. We are doing a couple more things, though. Imagine you've just attempted a callout and it failed. Why did it fail? If you've sent a bad request, then re-trying the same thing won't do you much, and the job will fail (gracefully, though, we're making sure of that) after the max number of attempts is reached. You'll get than info in a nice `Developer_Log__c` record, and you can go and fix your mistakes. 

But what if hat we're getting is a `500` code, for example? It could be the remote server is just down momentarily, that it has received too many requests at the same time and cannot respond immediately, or that it took a bit more time than usual to respond and our connection timed out. In most of those cases, you don't just want to re-try the callout *right back*. We might just get a better response if we just wait a bit. But that's not how chained queueables work. Once we've sent our job to the Apex Queue, we can't just ask for it to hold on right there for a bit, and run it some time in the future. 

Or can we? Well... isn't running jobs some given time in the future what Schedulable classes are for? That's exactly what they're there for! So, on a failed attempt, why not schedule a new job for some time in the future (as conveniently saved in the `Callout_Setting__mdt` Custom Metadata Type), and **only then** enqueue our next attempt? Yep, that works.

#### But when does it ever end?
Haven't we all asked that question before? Oh, you mean the job? Right. Well, we can't have a runaway job there, calling itself over and over again and using resources when it doesn't need them anymore. That's just being a bad neighbour. But, we can definitely handle ending our job at some point:
- If we fail a callout too many times in a row, we've got a maximum number of attempts defined in the `Callout_Setting__mdt` Custom Metadata Type. As soon as we hit that, a failed attempt will just quit the entire thing and stop retrying
- If we've got a successfull callout, we need to be able to tell when we've reached the last page, or our job will never end. So how do we do that? Well, imagine you're asking a friend to keep passing a bunch of books to you, 10 at a time, from a shelf behind your back. And they're reliable at that. If at some point your friend gives you anything less than 10 books, then you know the shelf is now empty. It could be that the last group of 10 books were the last ones, so your friend will have nothing else to pass along now, or it could be that less than 10 books are left, and that's all we're getting. One way or another, if we've asked for 10 items, and gotten less, it's time to round it up. As long as we keep getting the amount we've asked for, though, we know it's safe to keep going.

And when the job eventually ends (and it will, some way or another), we're once again gracefully wrapping up the whole thing, writing a nice `Developer_Log__c` for our admins with all the useful info we gathered throughout however many pages we went through, and closing the deal.

## The Disclaimer Section
Wow! So, chaining queueables sounds nice, and there's nothing stopping us from chaining one after the other. And I bet you're excited to go and write yourself some chained queueables in a nice dev org to try it out for yourself. Well... hold it right there for a second. We all know there's no such thing as a free meal, and there's no such thing as over-using the multitenant resources in Salesforce.

So, as far as chained queueables go, one thing to keep in mind. **And it's an important one:** If you're working in a sandbox environment, or in a Developer Edition org, then chained queueables are **NOT** infinite. You're limited to a stack depth of 5, and after that you're getting one of those not-so-nice, uncatchable governor limit Exceptions. And even if you're on one of those, Salesforce will throttle your queueable speed after the stack depth has reached 5, so future jobs will run *a lot slower*. (Though [that seems to have been sped up recently, though it's not documented anywhere](https://twitter.com/FishOfPrey/status/1493383965327380480)).

### Doesn't that defeat the entire purpose of this demo then?
Well, not quite. Give me some credit here. I'm 1928 words into this README, and I wouldn't be here if this was it. Remember how we're scheduling new attempts some time into the future to give the external system some breathing room before re-trying the same page? Well, turns out when we do that, we're also breaking up the stack depth of chained queueables. We're no calling a new queueable from our class, after all. We're calling a schedulable class, which by itself will enqueue a new job. And that's all we need. Once we get to a stack depth of 5, we'll break the chain, postpone our next page for a few seconds, and reset the counter. No throttling here. So we're going for a `Q-Q-Q-Q-Q- S - Q-Q...` pattern here. You'll fine some other devs around taking about a `Q-Q-Q-Q-Q- F -Q-Q...` pattern, using `@future` methods to break up queueable chains instead. But we've already got a Schedulable class doing some work for us, so why not use it?

## Ok, that's good and all, but I want to try it out for myself now. How do I do that?
Well, first of all, if you got here from the TL;DR at the top, at least go and read [the Disclaimer Section](# The Disclaimer Section) before moving on.

We're done? Good. Just clone the repo, and push the `force-app` directory in the `sfdx-project` into a fresh new org. You should have everything you need to test this out. Don't forget to go into the org and put yourself into the `Admins` public group if you want to get the `Developer_Log__c` info in the mail when a job is done.

Let's start with the basics, and see how the original Batch job breaks up when requesting a large amount of data. Go into an `Execute Anonymous` window, and run
```
GetCandidatesBatch batchJob = new GetCandidatesBatch(CandidatesCallout.Sizes.COMPLETE);
Database.executeBatch(batchJob)
```

Wait for a bit, and you should be getting an email titled `[ERROR]...` detailing how the Batch Job failed because of a `CalloutException`. If you don't get an email, you can just go and check the `Developer_Log__c` records in the org. The response we were trying to get was already way above the 12MB heap size. Ok, that's one of the catchable exceptions we could get, and we could get out gracefully from under that (we did get to write the `Developer_Log__c` and everything after all).

Now go ahead and run that again, but change the parameter from `CandidatesCallout.Sizes.COMPLETE` to `CandidatesCallout.Sizes.LARGE`. That will ask the Heroku app for just 10% of the records. Now, you can wait all you want, you're not getting an email this time. Or a `Developer_Log__c` to go look at. Instead, go to `Setup -> Apex Jobs` and sadly find out your job has failed with an uncatchable Exception: Apex heap size too large. What just happened? Well, it turns out 10% of the records from the app is just under 12MB. Small enough to get past the `CalloutException` due to the response size, but large enough than when we try to deserialize that and do anything with it, we're already past the allowed heap size. Bummer. And also, the whole point of this.

Let's go ahead and try the new and shiny Queueable class now. Go back into the `Execute Anonymous` window, and run
```
GetCandidatesPaged queueableJob = new GetCandidatesPaged(new GetCandidatesPaged.PagingAggregator(), 1, 500, 1, 1, false, CandidatesCallout.Sizes.MEDIUM)
System.enqueueJob(queueableJob)
```

If you want to know what all those parameters are, feel free to check the code. Enough to say, we're asking the api to get us the first 5000 records (1%) of the dataset, starting on record number 1 and getting pages of 500 records at a time. If you feel asking for less records this time around is cheating, just let me say, Developer Edition Orgs don't have enough storage space to handle the entire dataset even if we wanted to. If you've got access to a nice Enterprise edition (say, your company is a Salesforce Partner and can set one up for you), then go ahead and change `SMALL` for `COMPLETE` and knock yourself out.

Again, after a small while, you should either get an email, or be able to check the `Developer_Log__c` that was created when the job finished. There's nothing there yet? Check again in `Setup -> Apex Jobs` and make sure the process is not still running. Since you're there, check how we called for 10 total pages, and how there's a Schedulable Apex breaking up our chain after the first 5 Queueable jobs.

Cool, right? Now how about that re-trying failed attempts? Nothing seems to have failed so far (and it hasn't, if the Developer Log record doesn't say anything about it). Well, go and run that last bit of code again, just this time change the `false` parameter to `true`. We're now asking the class to call into the `faulty` endpoint, which has some probability of failing each time we call into it. Now, whether this ends up with the entire job managing to finish, or you hitting the max number of attempts is up to a coin toss. It's probabilistic after all. But whichever the case, you'll still get a Developer Log in the end, and this time there should be some callout error messages in the log for you to check out. They'll detail what page you were on when the callout failed, the attempt number, and the error message received.

And... That's it. Play around with it a bit more if you'd like. Go ahead and check the code, or feel free to write or open an issue here if you find anything worth noting.
