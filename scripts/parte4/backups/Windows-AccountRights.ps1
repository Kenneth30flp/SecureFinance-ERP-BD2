if(-not ('SecureFinance.AccountRights' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
namespace SecureFinance {
 public static class AccountRights {
  [StructLayout(LayoutKind.Sequential)] struct Attributes { public int Length; public IntPtr RootDirectory, ObjectName; public uint Flags; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
  [StructLayout(LayoutKind.Sequential)] struct Unicode { public ushort Length, MaximumLength; public IntPtr Buffer; }
  [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr name, ref Attributes attributes, uint access, out IntPtr handle);
  [DllImport("advapi32.dll")] static extern uint LsaEnumerateAccountRights(IntPtr handle, IntPtr sid, out IntPtr rights, out uint count);
  [DllImport("advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr handle, IntPtr sid, Unicode[] rights, uint count);
  [DllImport("advapi32.dll")] static extern uint LsaEnumerateAccountsWithUserRight(IntPtr handle, ref Unicode right, out IntPtr accounts, out uint count);
  [DllImport("advapi32.dll")] static extern uint LsaNtStatusToWinError(uint status);
  [DllImport("advapi32.dll")] static extern uint LsaFreeMemory(IntPtr buffer);
  [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr handle);
  public static string[] Read(string value) {
   var attributes=new Attributes(); attributes.Length=Marshal.SizeOf(typeof(Attributes));
   IntPtr handle=IntPtr.Zero, sid=IntPtr.Zero, rights=IntPtr.Zero;
   try {
    uint status=LsaOpenPolicy(IntPtr.Zero,ref attributes,0x800,out handle);
    if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status));
    var identifier=new SecurityIdentifier(value);var bytes=new byte[identifier.BinaryLength];identifier.GetBinaryForm(bytes,0);
    sid=Marshal.AllocHGlobal(bytes.Length);Marshal.Copy(bytes,0,sid,bytes.Length);
    uint count;status=LsaEnumerateAccountRights(handle,sid,out rights,out count);
    if(status==0xC0000034)return new string[0];
    if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status));
    var result=new string[count];int size=Marshal.SizeOf(typeof(Unicode));
    for(int i=0;i<count;i++){var item=(Unicode)Marshal.PtrToStructure(IntPtr.Add(rights,i*size),typeof(Unicode));result[i]=Marshal.PtrToStringUni(item.Buffer,item.Length/2);}
    return result;
   } finally {if(rights!=IntPtr.Zero)LsaFreeMemory(rights);if(sid!=IntPtr.Zero)Marshal.FreeHGlobal(sid);if(handle!=IntPtr.Zero)LsaClose(handle);}
  }
  public static string[] Assignees(string name) {
   if(name!="SeBatchLogonRight" && name!="SeDenyBatchLogonRight")throw new ArgumentException("Only batch rights may be inspected");
   var attributes=new Attributes();attributes.Length=Marshal.SizeOf(typeof(Attributes));IntPtr handle=IntPtr.Zero, buffer=IntPtr.Zero;
   var right=new Unicode();right.Buffer=Marshal.StringToHGlobalUni(name);right.Length=(ushort)(name.Length*2);right.MaximumLength=(ushort)(right.Length+2);
   try {
    uint status=LsaOpenPolicy(IntPtr.Zero,ref attributes,0x801,out handle);if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status));
    uint count;status=LsaEnumerateAccountsWithUserRight(handle,ref right,out buffer,out count);
    if(status==0x8000001A || status==0xC0000034)return new string[0];if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status));
    var result=new string[count];for(int i=0;i<count;i++)result[i]=new SecurityIdentifier(Marshal.ReadIntPtr(buffer,i*IntPtr.Size)).Value;return result;
   } finally {if(buffer!=IntPtr.Zero)LsaFreeMemory(buffer);Marshal.FreeHGlobal(right.Buffer);if(handle!=IntPtr.Zero)LsaClose(handle);}
  }
  public static void GrantBatchOnly(string value) {
   var attributes=new Attributes();attributes.Length=Marshal.SizeOf(typeof(Attributes));IntPtr handle=IntPtr.Zero,sid=IntPtr.Zero;
   var right=new Unicode();const string name="SeBatchLogonRight";right.Buffer=Marshal.StringToHGlobalUni(name);right.Length=(ushort)(name.Length*2);right.MaximumLength=(ushort)(right.Length+2);
   try {
    uint status=LsaOpenPolicy(IntPtr.Zero,ref attributes,0x810,out handle);if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status));
    var identifier=new SecurityIdentifier(value);var bytes=new byte[identifier.BinaryLength];identifier.GetBinaryForm(bytes,0);sid=Marshal.AllocHGlobal(bytes.Length);Marshal.Copy(bytes,0,sid,bytes.Length);
    status=LsaAddAccountRights(handle,sid,new[]{right},1);if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status));
   } finally {Marshal.FreeHGlobal(right.Buffer);if(sid!=IntPtr.Zero)Marshal.FreeHGlobal(sid);if(handle!=IntPtr.Zero)LsaClose(handle);}
  }
 }
}
'@
}
