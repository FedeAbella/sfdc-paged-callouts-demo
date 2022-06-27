# Salesforce Demo: Making callouts to paged endpoints using chained Queueable Apex

This repository is supposed to work as a demonstration on one way to make REST callouts in Salesforce to endpoints which work with paging, by using chained Queueable classes. It also shows how to deal with retrying failed callout attempts. If you feel like this is for you, please read on.

## The problem

On one of the projects I worked on, the customer had a Scheduled job running daily, which retrieved updates for some of their orders from an external system and updated info in their org. By the time I jumped onto the project, the job seemed to have failed a few times, without having been able to handle it, causing some de-sync between the customer's org and the external system. 

### Why was it failing? 
You see, the updates were made via a Batch Apex job, which performed the callout during its `start` method, and then processed the received updates in chunks, as appropriate. Really, there wasn't anything particularly wrong with the class as written, **but...** it just so happened that when we performed the callout, the external system exposed a **HUGE** amount of updates to our customers orders, most of which had to do with systems other than Salesforce, and were therefore irrelevant to us. The Architect at the time determined this was causing issues with governor limits (12MB of heap size for asynchronous jobs) during callouts. There was no way the external system would filter and expose just the updates that were relevant to us, so the most they compromised was allowing us to page through the updates a bit at a time, using parameters in the callout to ask the external system for a particular piece of data.

### But wait... how bad can that be?
Well, if you've run into Apex governor limits before (and if you're reading this, you probably have **a lot**, as we've all done), you know Exceptions raised from governon limits are *un-catchable*. That means there's no amount of `try - catch` blocks you can write than can save you from an Exception when you've bumped into one of those, making the entire job fail, the entire transaction roll back, and exiting as ungracefully as a bad stand-up comedian being heckled off the stage. No one wants that.

But, are we going to run into Apex governor limits? Well, could be. You see, Apex will give you 12MB of heap size to work with in asynchronous jobs. But it's not dumb, so if you're attempting a callout and the response is *already* larger than 12MB, instead you're getting a `CalloutException`, which most definitely can be caught and handled gracefully. Ha! No heckling for us.

**However...**, what if the response is *just* under 12MB, but any amount of post-processing we do with it (e.g.: deserializing the JSON) takes us over the 12MB heap size? Well, in that case, we're getting heckled off the stage again. So... yeah, it can get bad.

### Fine, that needs fixing
So, it came down to having to re-write the entire logic of fetching the updates, so we could page through the entire set of data one piece (and one callout) at a time, while also being able to tell when we were done.
> "Well... while we're at it, we might as well look into managing failed callouts, and not losing the entire job. Maybe re-trying those up to a max number of times. -- The Architect

Sure, let's just add that up to the list.

And so we come to this demo. This is a stripped down version of how we rebuilt the code to page through the data and handle re-trying failed callouts. It focuses just on the logic needed to make the callouts, and not on any of the post-processing one might want to do with the data received.

## The data

Ok, I'm obviously not going through this demo using any of our customer's endpoints or data, so I've set up a very simple Heroku app that will return either paged or non-paged data. That way we can see how both scenarios are handled. 

**Disclaimer:** Both the Heroku api and the script used to build the fake data are made in Python. I can handle myself around Python, but I'm surely not as good with it as with Apex. Plus, this was my first time building an api using Flask or Heroku, so don't expect that part to be as polished as the Apex bits. That being said, any constructive criticism about that is also welcome.
- You can find the script used to create the large amount of data under [`data-maker`](https://github.com/FedeAbella/salesforce-paged-callouts-demo/tree/master/data-maker). It's currently built to return a `csv` of 500k "Candidates" with their name, current position, current company and some external ID.
- In [`data-api`](https://github.com/FedeAbella/salesforce-paged-callouts-demo/tree/master/data-api) you'll find the Flask api that is called to return the data, as well as the required files for exposing it in Heroku.

## The relevant bit

The main point is definitely in the [`sfdx-project`](https://github.com/FedeAbella/salesforce-paged-callouts-demo/tree/master/sfdx-project) directory. There you'll find all the relevant metadata needed to replicate this yourself, so feel free to just push that into a fresh new org and try it yourself. However, see the `README.md` file there for more information on what each class does, and what it's there for. Plus, some extra considerations. 
