/////////////////////////////////////////////////////////////////////////////
// Name:        wx/protocol/http.h
// Purpose:     HTTP protocol
// Author:      Guilhem Lavaux
// Modified by: Simo Virokannas (authentication, Dec 2005)
// Created:     August 1997
// Copyright:   (c) 1997, 1998 Guilhem Lavaux
// Licence:     wxWindows licence
/////////////////////////////////////////////////////////////////////////////
#ifndef _WX_HTTP_H
#define _WX_HTTP_H

#include "wx/defs.h"

#if wxUSE_PROTOCOL_HTTP

#include "wx/protocol/protocol.h"
#include "wx/buffer.h"

#include <unordered_map>

class WXDLLIMPEXP_NET wxHTTP : public wxProtocol
{
public:
    wxHTTP();
    virtual ~wxHTTP();

    virtual bool Connect(const wxString& host, unsigned short port);
    virtual bool Connect(const wxString& host) override { return Connect(host, 0); }
    virtual bool Connect(const wxSockAddress& addr, bool wait = true) override;
    bool Abort() override;

    wxInputStream *GetInputStream(const wxString& path) override;

    wxString GetContentType() const override;
    wxString GetHeader(const wxString& header) const;
    int GetResponse() const { return m_http_response; }

    void SetMethod(const wxString& method) { m_method = method; }
    void SetHeader(const wxString& header, const wxString& h_data);
    bool SetPostText(const wxString& contentType,
                     const wxString& data,
                     const wxMBConv& conv = wxConvUTF8);
    bool SetPostBuffer(const wxString& contentType, const wxMemoryBuffer& data);
    void SetProxyMode(bool on);

    /* Cookies */
    wxString GetCookie(const wxString& cookie) const;
    bool HasCookies() const { return m_cookies.size() > 0; }

    // Use the other SetPostBuffer() overload or SetPostText() instead.
    wxDEPRECATED(void SetPostBuffer(const wxString& post_buf));

protected:
    using wxHeadersMap = std::unordered_map<wxString, wxString>;
    typedef wxHeadersMap::iterator wxHeaderIterator;
    typedef wxHeadersMap::const_iterator wxHeaderConstIterator;

    using wxCookiesMap = std::unordered_map<wxString, wxString>;
    typedef wxCookiesMap::iterator wxCookieIterator;
    typedef wxCookiesMap::const_iterator wxCookieConstIterator;

    bool BuildRequest(const wxString& path, const wxString& method);
    void SendHeaders();
    bool ParseHeaders();

    wxString GenerateAuthString(const wxString& user, const wxString& pass) const;

    // find the header in m_headers
    wxHeaderIterator FindHeader(const wxString& header);
    wxHeaderConstIterator FindHeader(const wxString& header) const;
    wxCookieIterator FindCookie(const wxString& cookie);
    wxCookieConstIterator FindCookie(const wxString& cookie) const;

    // deletes the header value strings
    void ClearHeaders();
    void ClearCookies();

    // internal variables:

    wxString m_method;
    wxCookiesMap m_cookies;

    wxHeadersMap m_headers;
    bool m_read,
         m_proxy_mode;
    wxSockAddress *m_addr;
    wxMemoryBuffer m_postBuffer;
    wxString       m_contentType;
    int m_http_response;

    wxDECLARE_DYNAMIC_CLASS(wxHTTP);
    DECLARE_PROTOCOL(wxHTTP)
    wxDECLARE_NO_COPY_CLASS(wxHTTP);
};

#endif // wxUSE_PROTOCOL_HTTP

#endif // _WX_HTTP_H

