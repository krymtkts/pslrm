using System.Collections.Generic;
using System.Threading;

public static class PslrmTestMutexOwner
{
    private static readonly List<Mutex> OwnedMutexes = new List<Mutex>();

    public static Thread StartAbandoned(string name, ManualResetEventSlim acquired)
    {
        var thread = new Thread(() =>
        {
            var mutex = new Mutex(false, name);
            lock (OwnedMutexes)
            {
                OwnedMutexes.Add(mutex);
            }

            mutex.WaitOne();
            acquired.Set();
        });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }

    public static void DisposeAll()
    {
        List<Mutex> mutexes;
        lock (OwnedMutexes)
        {
            mutexes = new List<Mutex>(OwnedMutexes);
            OwnedMutexes.Clear();
        }

        foreach (var mutex in mutexes)
        {
            mutex.Dispose();
        }
    }
}

public static class PslrmTestImportProbe
{
    public static readonly ManualResetEventSlim FirstImportEntered = new ManualResetEventSlim(false);
    public static readonly ManualResetEventSlim FirstInvocationReady = new ManualResetEventSlim(false);
    public static readonly ManualResetEventSlim SecondInvocationReady = new ManualResetEventSlim(false);
    public static readonly ManualResetEventSlim SecondImportEntered = new ManualResetEventSlim(false);
    public static readonly ManualResetEventSlim ReleaseInvocations = new ManualResetEventSlim(false);
    public static readonly ManualResetEventSlim ReleaseImports = new ManualResetEventSlim(false);

    private static int importCount;
    private static int activeImportCount;
    private static int maxActiveImportCount;

    public static void Reset()
    {
        FirstImportEntered.Reset();
        FirstInvocationReady.Reset();
        SecondInvocationReady.Reset();
        SecondImportEntered.Reset();
        ReleaseInvocations.Reset();
        ReleaseImports.Reset();
        Interlocked.Exchange(ref importCount, 0);
        Interlocked.Exchange(ref activeImportCount, 0);
        Interlocked.Exchange(ref maxActiveImportCount, 0);
    }

    public static void EnterImport()
    {
        var activeCount = Interlocked.Increment(ref activeImportCount);
        UpdateMaximum(activeCount);

        var currentImport = Interlocked.Increment(ref importCount);
        if (currentImport == 1)
        {
            FirstImportEntered.Set();
        }
        else if (currentImport == 2)
        {
            SecondImportEntered.Set();
        }

        ReleaseImports.Wait();
        Interlocked.Decrement(ref activeImportCount);
    }

    public static int GetMaxActiveImportCount()
    {
        return Interlocked.CompareExchange(ref maxActiveImportCount, 0, 0);
    }

    private static void UpdateMaximum(int activeCount)
    {
        var currentMaximum = Interlocked.CompareExchange(ref maxActiveImportCount, 0, 0);
        while (activeCount > currentMaximum)
        {
            var previousMaximum = Interlocked.CompareExchange(
                ref maxActiveImportCount,
                activeCount,
                currentMaximum
            );
            if (previousMaximum == currentMaximum)
            {
                return;
            }

            currentMaximum = previousMaximum;
        }
    }
}
