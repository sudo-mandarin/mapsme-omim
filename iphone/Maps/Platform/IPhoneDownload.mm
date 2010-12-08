#import "IPhoneDownload.h"

#include "../../platform/download_manager.hpp"

#define TIMEOUT_IN_SECONDS 15.0

@implementation IPhoneDownload

- (string const &) Url
{
  return m_url;
}

- (void) Cancel
{
	if (m_connection)
  	[m_connection cancel];
  m_progressObserver.clear();
  m_finishObserver.clear();
}

- (void) dealloc
{
//  NSLog(@"~IPhoneDownload() for url: %s", m_url.c_str());
  if (m_connection)
  {
  	[m_connection cancel];
  	[m_connection release];
  }
  // Non-zero means that download is canceled
	if (m_file)
  {
  	fclose(m_file);
    if (!m_requestedFileName.empty())
   		remove((m_requestedFileName + DOWNLOADING_FILE_EXTENSION).c_str());
  }
	[super dealloc];
}

- (BOOL) StartDownloadWithUrl: (char const *)originalUrl andFile: (char const *)file
		andFinishFunc: (TDownloadFinishedFunction &)finishFunc andProgressFunc: (TDownloadProgressFunction &)progressFunc
    andUseResume: (BOOL)resume
{
	m_finishObserver = finishFunc;
  m_progressObserver = progressFunc;
  
	// try to create file first
  std::string tmpFile = file;
  tmpFile += DOWNLOADING_FILE_EXTENSION;
  m_file = fopen(tmpFile.c_str(), resume ? "ab" : "wb");
  if (m_file == 0)
  {
  	NSLog(@"Error opening %s file for download: %s", tmpFile.c_str(), strerror(errno));
  	// notify observer about error and exit
    if (m_finishObserver)
    	m_finishObserver(originalUrl, false);
    return NO;
  }

	m_requestedFileName = file;
	m_url = originalUrl;
 
  // Create the request.
	NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString: [NSString stringWithUTF8String:m_url.c_str()]]
  		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:TIMEOUT_IN_SECONDS];
  long long fileSize = ftello(m_file);
  if (resume && fileSize > 0)
  {
		NSString * val = [[NSString alloc] initWithFormat: @"bytes=%qi-", fileSize];
		[request addValue:val forHTTPHeaderField:@"Range"];
		[val release];
  }
	// create the connection with the request and start loading the data
	m_connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
//  [request release];
	if (m_connection == 0)
  {
		NSLog(@"Can't create connection for url %s", originalUrl);
		// notify observer about error and exit
    if (m_finishObserver)
    	m_finishObserver(originalUrl, false);
    return NO;
	}

  return YES;
}

- (void) connection: (NSURLConnection *)connection didReceiveResponse: (NSURLResponse *)response
{
	// This method is called when the server has determined that it
	// has enough information to create the NSURLResponse.
 
	// check if this is OK (not a 404 or the like)
  if ([response respondsToSelector:@selector(statusCode)])
  {
  	NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    if (statusCode < 200 || statusCode > 299)
    {
    	NSLog(@"Received HTTP error code %d, canceling download", statusCode);
      // deleting file
      fclose(m_file);
      m_file = 0;
      remove((m_requestedFileName + DOWNLOADING_FILE_EXTENSION).c_str());
      // notify user
		  if (m_finishObserver)
      	m_finishObserver(m_url.c_str(), false);
  		// and selfdestruct...
  		GetDownloadManager().CancelDownload(m_url.c_str());
			return;
    }
  }
 
  m_projectedFileSize = [response expectedContentLength];
  // if server doesn't support resume, make sure we're downloading file from scratch
	if (m_projectedFileSize < 0)
  {
  	fclose(m_file);
    m_file = fopen((m_requestedFileName + DOWNLOADING_FILE_EXTENSION).c_str(), "wb");
  }
  NSLog(@"Projected file size: %qi", m_projectedFileSize);
}

- (void) connection: (NSURLConnection *)connection didReceiveData: (NSData *)data
{
	// Append the new data
	fwrite([data bytes], 1, [data length], m_file);
  if (m_progressObserver)
	  m_progressObserver(m_url.c_str(), TDownloadProgress(ftello(m_file), m_projectedFileSize));
}

- (void) connection: (NSURLConnection *)connection didFailWithError: (NSError *)error
{
	// inform the user
  NSLog(@"Connection failed! Error - %@ %s", [error localizedDescription], m_url.c_str());
  if (m_finishObserver)
	  m_finishObserver(m_url.c_str(), false);
  // and selfdestruct...
  GetDownloadManager().CancelDownload(m_url.c_str());
}

- (void) connectionDidFinishLoading: (NSURLConnection *)connection
{
	// close file
  fclose(m_file);
  m_file = 0;
  // remote temporary extension from downloaded file
  remove(m_requestedFileName.c_str());
  bool resultForGUI = true;
  if (rename((m_requestedFileName + DOWNLOADING_FILE_EXTENSION).c_str(), m_requestedFileName.c_str()))
  {
  	resultForGUI = false;
  	NSLog(@"Can't rename to file %s", m_requestedFileName.c_str());    
  }
  else
  {
  	NSLog(@"Successfully downloaded %s", m_url.c_str());
  }
  
  if (m_finishObserver)
	  m_finishObserver(m_url.c_str(), resultForGUI);
  // and selfdestruct...
  GetDownloadManager().CancelDownload(m_url.c_str());
}

@end
