using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace Kontur {
 public static class Bootstrap {
  const string Version = "1.1.0";
  static Assembly Package { get { return typeof(Bootstrap).Assembly; } }
  static string Digest(Stream stream) {
   using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
  }
  static string SafePath(string root,string relative) {
   string prefix=Path.GetFullPath(root)+Path.DirectorySeparatorChar;
   string full=Path.GetFullPath(Path.Combine(root,relative.Replace('/',Path.DirectorySeparatorChar)));
   if(!full.StartsWith(prefix,StringComparison.OrdinalIgnoreCase)) throw new IOException("Недопустимый путь в пакете.");
   return full;
  }
  static void Verify(string root) {
   using(var resource=Package.GetManifestResourceStream("Kontur.Integrity"))
   using(var reader=new StreamReader(resource,Encoding.UTF8)) {
    string line;
    while((line=reader.ReadLine())!=null) {
     if(line.Length<67) throw new IOException("Повреждён список компонентов.");
     string path=SafePath(root,line.Substring(66));
     if(!File.Exists(path)) throw new IOException("Не найден компонент: "+line.Substring(66));
     using(var file=File.OpenRead(path)) if(Digest(file)!=line.Substring(0,64))
      throw new IOException("Изменён или повреждён компонент: "+line.Substring(66)+". Закройте Контур и переименуйте папку runtime в %LOCALAPPDATA%\\Kontur, затем повторите запуск.");
    }
   }
  }
  // Exposed for isolated packaging tests. Does not start winws or alter hosts.
  public static string PrepareRuntime(string storage) {
   string fingerprint;
   using(var payload=Package.GetManifestResourceStream("Kontur.Payload")) fingerprint=Digest(payload);
   string container=Path.Combine(storage,"runtime",Version);
   Directory.CreateDirectory(container);
   string installed=Path.Combine(container,fingerprint.Substring(0,16));
   using(var extraction=new Mutex(false,"Local\\Kontur.Payload.Extraction")) {
    bool acquired=false;
    try {
     try {acquired=extraction.WaitOne(TimeSpan.FromSeconds(60));} catch(AbandonedMutexException) {acquired=true;}
     if(!acquired) throw new IOException("Подготовка Контура уже выполняется. Повторите запуск через минуту.");
     if(!Directory.Exists(installed)) {
      string stage=Path.Combine(container,"preparing-"+Guid.NewGuid().ToString("N"));
      Directory.CreateDirectory(stage);
      using(var stream=Package.GetManifestResourceStream("Kontur.Payload"))
      using(var zip=new ZipArchive(stream,ZipArchiveMode.Read)) {
       foreach(var entry in zip.Entries) {
        string destination=SafePath(stage,entry.FullName);
        if(entry.FullName.EndsWith("/")) {Directory.CreateDirectory(destination);continue;}
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        using(var source=entry.Open()) using(var output=new FileStream(destination,FileMode.CreateNew,FileAccess.Write)) source.CopyTo(output);
       }
      }
      Verify(stage);
      File.WriteAllText(Path.Combine(stage,".complete"),fingerprint,Encoding.ASCII);
      Directory.Move(stage,installed);
     }
     if(!File.Exists(Path.Combine(installed,".complete")) || File.ReadAllText(Path.Combine(installed,".complete"))!=fingerprint)
      throw new IOException("Подготовка компонентов не завершена. Переименуйте папку runtime в %LOCALAPPDATA%\\Kontur и запустите EXE снова.");
     Verify(installed);
     return installed;
    } finally {if(acquired) extraction.ReleaseMutex();}
   }
  }
  [STAThread] public static void Main(string[] args) {
   Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   bool owned;
   using(var instance=new Mutex(true,"Local\\Kontur.Launcher",out owned)) {
    if(!owned) {MessageBox.Show("Контур уже открыт. Проверьте панель задач и системный трей.","Контур");return;}
    try {
     string storage=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Kontur");
     string runtime=PrepareRuntime(storage);
     Application.Run(new MainForm(runtime));
    } catch(Exception ex) {MessageBox.Show(ex.Message,"Контур — ошибка запуска",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
   }
  }
 }
}
