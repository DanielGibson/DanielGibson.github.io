// use of ajax vs getJSON for headers use to get markdown (body vs body_htmml)
// todo: pages, configure issue url, open in new window?

/*
 * based on Don Williamson's code, see
 * http://donw.io/post/github-comments/#using-github-for-comments
 * and https://github.com/dwilliamson/donw.io/blob/master/public/js/github-comments.js
 * 
 * Released under MIT license, see https://github.com/dwilliamson/donw.io/issues/1#issuecomment-310507318
 * 
 * Modified by Daniel Gibson to use plain Javascript instead of JQuery.
 * 
 */
 
function ParseLinkHeader(link)
{
    var links = { };
    if (link)
    {
        var entries = link.split(",");
        for (var i in entries)
        {
            var entry = entries[i];
            var link = { };
            link.name = entry.match(/rel=\"([^\"]*)/)[1];
            link.url = entry.match(/<([^>]*)/)[1];
            link.page = entry.match(/page=(\d+).*$/)[1];
            links[link.name] = link;
        }
    }
    return links;
}

function AddComments(xhreq, page_id, issueURL, comment_id)
{
    var gh_comments_list = document.querySelector("#gh-comments-list");
    var gh_load_comments = document.querySelector("#gh-load-comments");
    
    var comments = JSON.parse(xhreq.response);
    
    // Add post button to first page
    if (page_id == 1)
    {
        var newPostHtml = "<a href='" + issueURL + "#new_comment_field' rel='nofollow' target='_blank' class='btn'>";
        if(comments.length == 0)
            newPostHtml += "Post the first comment on Github";
        else
            newPostHtml += "Post a comment on Github";
        newPostHtml += "</a>";
        gh_comments_list.insertAdjacentHTML("beforeend", newPostHtml);
    }

    // Individual comments
    for (i=0; i<comments.length; ++i)
    {
        var comment = comments[i];
        var date = new Date(comment.created_at);

        var t = "<div id='gh-comment'>";
        t += "<img src='" + comment.user.avatar_url + "' width='24px'>";
        t += "<b><a href='" + comment.user.html_url + "' class='comment-user-link'>" + comment.user.login + "</a></b>";
        t += " posted at ";
        t += "<em>" + date.toUTCString() + "</em>";
        t += "<div id='gh-comment-hr'></div>";
        t += comment.body_html;
        t += "</div>";
        gh_comments_list.insertAdjacentHTML("beforeend", t);
    }

    // Setup comments button if there are more pages to display
    var links = ParseLinkHeader(xhreq.getResponseHeader("Link"));
    if ("next" in links)
    {
        gh_load_comments.onclick = function(){ 
            DoGithubComments(comment_id, page_id+1); 
        };
        gh_load_comments.style.display = '';
    }
    else
    {
        gh_load_comments.style.display = 'none';
    }
}

function DoGithubComments(comment_id, page_id)
{
    var repo_name = "DanielGibson/DanielGibson.github.io";
    //var repo_name = "dwilliamson/donw.io";

    if (page_id === undefined)
        page_id = 1;

    var api_url = "https://api.github.com/repos/" + repo_name;
    var api_issue_url = api_url + "/issues/" + comment_id;
    var api_comments_url = api_issue_url + "/comments" + "?page=" + page_id;

    var issueURL = "https://github.com/" + repo_name + "/issues/" + comment_id;
    
    var req = new XMLHttpRequest();
    req.open("GET", api_comments_url);
    req.setRequestHeader("Accept", "application/vnd.github.v3.html+json");
    
    req.onreadystatechange = function() {
        if (req.readyState === XMLHttpRequest.DONE)
        {
            if (req.status === 200)
                AddComments(req, page_id, issueURL, comment_id);
            else if(req.status === 403) // TODO: && rate limited
            {
                var t = "Exceeded the Github API rate limit, try again in ";
                t += 60; // FIXME: get timestamp from request and current timestamp etc
                t += " minutes or just view the comments directly at<br>";
                t += "<a href='" + issueURL + "' rel='nofollow' target='_blank' rel='nofollow' class='btn'>Github</a>";
                document.querySelector("#gh-comments-list").insertAdjacentHTML("beforeend", t);
            }
            else
                document.querySelector("#gh-comments-list").insertAdjacentHTML("beforeend", "Couldn't load comments");
        }
    };
    
    req.send();
}
