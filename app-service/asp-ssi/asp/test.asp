<%@ Language="VBScript" %>
<html>
  <head></head>
    <body>
      <h1>VBScript Powered ASP page on Azure Web Apps </h1>
<%  
Dim dtmHour 
dtmHour = Hour(Now()) 

If dtmHour < 12 Then 
  strGreeting = "Good Morning!" 
Else   
  strGreeting = "Hello!" 
End If    
%>  
        
    <%= strGreeting %> 
    <br />
    <%= Now() %>
    <br />
    <h2>Content from text.txt:</h2>
    <!--#include file="text.txt"-->
    <br />
    <h2>Content from include.inc:</h2>
    <!--#include file="include.inc"-->
    <br />
    <h2>Content from include.asp:</h2>
    <!--#include file="include.asp"-->
  </body>
</html>