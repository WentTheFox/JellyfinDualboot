// Windows service wrapper: start = mount-config.ps1, stop/shutdown = unmount-config.ps1.
// If the WSL2 distro goes away underneath us (wsl --shutdown, crash), the service stops itself.
// Built by install-service.ps1 with the .NET Framework csc.exe, no extra tooling needed.
// Args (from the service ImagePath): <project dir> [distro]
using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;
using System.Threading;

class JellyfinService : ServiceBase
{
    const int StepMs = 180000;
    readonly string project;
    readonly string distro;
    readonly string log;
    Process keepAlive;
    volatile bool stopping;
    volatile bool distroGone;

    JellyfinService(string project, string distro)
    {
        this.project = project;
        this.distro = distro;
        log = Path.Combine(project, "windows", "bin", "service.log");
        ServiceName = "JellyfinDualboot";
        CanShutdown = true;
        CanStop = true;
    }

    static void Main(string[] args)
    {
        if (args.Length < 1) { Console.Error.WriteLine("usage: JellyfinService.exe <project dir> [distro]"); return; }
        Run(new JellyfinService(args[0], args.Length > 1 ? args[1] : ""));
    }

    void Log(string msg)
    {
        try { File.AppendAllText(log, DateTime.Now.ToString("s") + " " + msg + Environment.NewLine); } catch { }
    }

    int Script(string name)
    {
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + Path.Combine(project, "windows", name) + "\""
            + (distro != "" ? " -Distro \"" + distro + "\"" : ""))
        { UseShellExecute = false, CreateNoWindow = true };
        using (var p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }

    protected override void OnStart(string[] args)
    {
        RequestAdditionalTime(StepMs);
        Log("start");
        if (Script("mount-config.ps1") != 0)
            throw new InvalidOperationException("mount-config.ps1 failed");

        // Hold the distro open while we run; when this process exits the distro is gone (wsl --shutdown, crash).
        // stdin must stay open or wsl.exe returns immediately when started without a console.
        // wsl.exe takes quotes literally ("Debian" -> no such distro), so pass the name bare.
        var da = distro != "" ? "-d " + distro + " " : "";
        keepAlive = new Process();
        keepAlive.StartInfo = new ProcessStartInfo("wsl.exe", da + "-- sleep infinity")
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true };
        keepAlive.EnableRaisingEvents = true;
        keepAlive.Exited += delegate
        {
            if (stopping) return;
            Log("keep-alive exited, code " + keepAlive.ExitCode);
            // The keep-alive can fail on its own; only stop if the distro is really gone.
            if (DistroRunning()) { Log("distro still running, ignoring"); return; }
            distroGone = true;
            Log("distro gone, stopping service");
            new Thread(delegate () { Stop(); }).Start();
        };
        keepAlive.Start();
        Log("keep-alive pid " + keepAlive.Id);
    }

    bool DistroRunning()
    {
        try
        {
            var psi = new ProcessStartInfo("wsl.exe", "-l --running -q")
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, StandardOutputEncoding = System.Text.Encoding.Unicode };
            using (var p = Process.Start(psi))
            {
                var o = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                // empty output = nothing running; with no -d given, any running distro counts
                return distro != "" ? o.IndexOf(distro, StringComparison.OrdinalIgnoreCase) >= 0 : o.Trim().Length > 0;
            }
        }
        catch (Exception e) { Log("DistroRunning failed: " + e.Message); return true; }
    }

    void Down()
    {
        stopping = true;
        RequestAdditionalTime(StepMs);
        Log("stop (distroGone=" + distroGone + ")");
        if (distroGone)
        {
            // Don't relaunch the distro just to run ./jf down; the container died with it.
            var vhdx = Path.Combine(project, "data", "jellyfin-config.vhdx");
            Process.Start(new ProcessStartInfo("wsl.exe", "--unmount " + vhdx)
            { UseShellExecute = false, CreateNoWindow = true }).WaitForExit();
        }
        else
        {
            Script("unmount-config.ps1"); // ./jf down inside WSL2, then wsl --unmount
        }
        try { if (keepAlive != null && !keepAlive.HasExited) keepAlive.Kill(); } catch { }
        Log("stopped");
    }

    protected override void OnStop() { Down(); }
    protected override void OnShutdown() { Down(); }
}
