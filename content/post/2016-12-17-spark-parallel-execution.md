+++
date        = "2016-12-17T16:04:45+11:00"
title       = "Spark Parallel Job Execution"
tags        = [ "Development", "Spark" ]
categories  = [ "Development", "Spark" ]
+++

A pretty common use case for [Spark](http://spark.apache.org/) is to run many jobs in parallel. Spark is excellent at running stages in parallel after constructing the job dag, but this doesn't help us to run two entirely independent jobs in the same [Spark](http://spark.apache.org/) applciation at the same time. Some of the use cases I can think of for parallel job execution include steps in an etl pipeline in which we are pulling data from several remote sources and landing them into our an hdfs cluster.

### Threading and Thread Safety

Every spark application needs a spark session (context) to configure and execute actions. The SparkSession object is thread safe and can be passed around your spark application as you see fit.

### A Sequential Example

Consider a spark 2.x application with a couple of functions that write data to hdfs.

```scala
import org.apache.spark.sql.SparkSession

object FancyApp {
  def def appMain(args: Array[String]) = {
    // configure spark
    val spark = SparkSession
        .builder
        .appName("parjobs")
        .getOrCreate()

    val df = spark.sparkContext.parallelize(1 to 100).toDF
    doFancyDistinct(df, "hdfs:///dis.parquet")
    doFancySum(df, "hdfs:///sum.parquet")
  }

  def doFancyDistinct(df: DataFrame, outPath: String) = df.distinct.write.parquet(outPath)


  def doFancySum(df: DataFrame, outPath: String) = df.agg(sum("value")).write.parquet(outPath)

}
```

That's all well and good, but spark will execute the two actions sequentially which isn't necessary for these two independent actions. We can do better.

### A Bad Sequential Example

A quick google for 'scala asynchronous programming' will quickly lead you to example for scala futures. If you wade in following some online examples you might end up with something that looks like the following...

```scala
import org.apache.spark.sql.SparkSession
import scala.concurrent._
import scala.concurrent.duration._
import scala.concurrent.ExecutionContext.Implicits.global

object FancyApp {
  def def appMain(args: Array[String]) = {
    // configure spark
    val spark = SparkSession
        .builder
        .appName("parjobs")
        .getOrCreate()

    val df = spark.sparkContext.parallelize(1 to 100).toDF
    val taskA = doFancyDistinct(df, "hdfs:///dis.parquet")
    val taskB = doFancySum(df, "hdfs:///sum.parquet")
    // Now wait for the tasks to finish before exiting the app
    Await.result(Future.sequence(Seq(taskA,taskB)), Duration(1, MINUTES))
  }

  def doFancyDistinct(df: DataFrame, outPath: String) = Future { df.distinct.write.parquet(outPath) }

  def doFancySum(df: DataFrame, outPath: String) = Future { df.agg(sum("value")).write.parquet(outPath) }
}
```

The ExecutionContext is a context for managing parallel operations. The actual threading model can be explicitly provided by the programmer, or a global default is used (which is a ForkJoinPool) as we have done here with the following line...

```scala
import scala.concurrent.ExecutionContext.Implicits.global
```

The trouble with the global execution context is that it has no idea that you are launching spark jobs on a cluster. By default the global execution context provides the same number of threads as processors in the system running the code. In the case of our spark application, that'll be the spark driver. We can do better than this.

### A Better Sequential Example

We need to take control of our threading strategy, and we need to write our functions more generally, such that they can be re-used with different threading models in mind.

Let's start by rewriting our functions to allow fine grained control over exactly which execution context will manage the threading for a particular function call. This addition of this implicit parameter allows they calling code to specify exactly which ExecutionContext should be used when running the function.

```scala
def doFancyDistinct(df: DataFrame, outPath: String)(implicit xc: ExecutionContext) = Future {
  df.distinct.write.parquet(outPath)
}
```

Now let's come up with a better strategy than the default global execution context. We want to be able to define exactly what we want our parllelism will be.

```scala
import org.apache.spark.sql.SparkSession
import import java.util.concurrent.Executors
import scala.concurrent._
import scala.concurrent.duration._

object FancyApp {
  def def appMain(args: Array[String]) = {
    // configure spark
    val spark = SparkSession
        .builder
        .appName("parjobs")
        .getOrCreate()

    // Set number of threads via a configuration property
    val pool = Executors.newFixedThreadPool(5)
    // create the implicit ExecutionContext based on our thread pool
    implicit val xc = ExecutionContext.fromExecutorService(pool)
    val df = spark.sparkContext.parallelize(1 to 100).toDF
    val taskA = doFancyDistinct(df, "hdfs:///dis.parquet")
    val taskB = doFancySum(df, "hdfs:///sum.parquet")
    // Now wait for the tasks to finish before exiting the app
    Await.result(Future.sequence(Seq(taskA,taskB)), Duration(1, MINUTES))
  }

  def doFancyDistinct(df: DataFrame, outPath: String)(implicit xc: ExecutionContext) = Future {
    df.distinct.write.parquet(outPath)
  }

  def doFancySum(df: DataFrame, outPath: String)(implicit xc: ExecutionContext) = Future {
    df.agg(sum("value")).write.parquet(outPath) 
  }
}
```

The nature of scala implicits will mean that our fancy functions will be called from the appMain entrypoint using the in-scope execution context xc.
