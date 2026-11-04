using System;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace SecureFinance {
 public sealed class WorkerAccess : IDisposable {
  [StructLayout(LayoutKind.Sequential)] struct Mapping { public uint Read, Write, Execute, All; }
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LogonUserW(string user,string domain,IntPtr password,int type,int provider,out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool DuplicateToken(IntPtr token,int level,out IntPtr duplicate);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool AccessCheck(byte[] descriptor,IntPtr token,uint desired,ref Mapping mapping,IntPtr privileges,ref uint length,out uint granted,out bool status);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  IntPtr token; WindowsIdentity identity;
  public WorkerAccess(string account,SecureString password) {
   IntPtr secret=IntPtr.Zero,primary=IntPtr.Zero;
   try {
    string domain=null,user=account;int slash=account.IndexOf('\\');if(slash>=0){domain=account.Substring(0,slash);user=account.Substring(slash+1);}
    secret=Marshal.SecureStringToGlobalAllocUnicode(password);
    if(!LogonUserW(user,domain,secret,4,0,out primary))throw new Win32Exception(Marshal.GetLastWin32Error(),"Batch token unavailable; inspect rights/credential without resetting either.");
    if(!DuplicateToken(primary,2,out token))throw new Win32Exception(Marshal.GetLastWin32Error());
    identity=new WindowsIdentity(token);
   } catch {Dispose();throw;} finally {if(primary!=IntPtr.Zero)CloseHandle(primary);if(secret!=IntPtr.Zero)Marshal.ZeroFreeGlobalAllocUnicode(secret);}
  }
  public string Sid { get { return identity.User.Value; } }
  public bool IsAdministrator { get { return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator); } }
  public string[] GroupSids { get {var result=new string[identity.Groups.Count+1];result[0]=Sid;for(int i=0;i<identity.Groups.Count;i++)result[i+1]=identity.Groups[i].Value;return result;} }
  public uint AccessMask(byte[] descriptor) {
   if(token==IntPtr.Zero)throw new ObjectDisposedException("WorkerAccess");
   var mapping=new Mapping {Read=0x120089,Write=0x120116,Execute=0x1200A0,All=0x1F01FF};
   uint length=1024,granted;bool allowed;IntPtr buffer=Marshal.AllocHGlobal((int)length);
   try {
    if(!AccessCheck(descriptor,token,0x02000000,ref mapping,buffer,ref length,out granted,out allowed)){
     int error=Marshal.GetLastWin32Error();if(error!=122)throw new Win32Exception(error);
     Marshal.FreeHGlobal(buffer);buffer=IntPtr.Zero;buffer=Marshal.AllocHGlobal(checked((int)length));
     if(!AccessCheck(descriptor,token,0x02000000,ref mapping,buffer,ref length,out granted,out allowed))throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    return allowed?granted:0;
   } finally {if(buffer!=IntPtr.Zero)Marshal.FreeHGlobal(buffer);}
  }
  public void Dispose(){if(identity!=null){identity.Dispose();identity=null;}if(token!=IntPtr.Zero){CloseHandle(token);token=IntPtr.Zero;}}
 }
 public sealed class VolumeFact {
  public string Root {get;set;} public string VolumeId {get;set;} public string FreeBytes {get;set;} public string TotalBytes {get;set;} public string SampledAtUTC {get;set;}
 }
 public static class VolumeInspection {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetDiskFreeSpaceExW(string path,out ulong available,out ulong total,out ulong free);
  public static VolumeFact Read(string root) {
   using(var handle=CreateFileW(root,0x80,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero)) {
    if(handle.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
    var path=new StringBuilder(32768);uint length=GetFinalPathNameByHandleW(handle,path,(uint)path.Capacity,1);
    if(length==0||length>=path.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error());
    string resolved=path.ToString();int end=resolved.IndexOf("}\\",StringComparison.Ordinal);
    if(!resolved.StartsWith("\\\\?\\Volume{",StringComparison.OrdinalIgnoreCase)||end<0)throw new InvalidOperationException("Cannot establish local destination volume identity.");
    string volume=resolved.Substring(0,end+2);ulong available,total,free;
    if(!GetDiskFreeSpaceExW(volume,out available,out total,out free))throw new Win32Exception(Marshal.GetLastWin32Error());
    return new VolumeFact {Root=root,VolumeId=volume,FreeBytes=available.ToString(CultureInfo.InvariantCulture),TotalBytes=total.ToString(CultureInfo.InvariantCulture),SampledAtUTC=DateTime.UtcNow.ToString("o")};
   }
  }
 }
}
